# IPU3 ImgU — Phase B: test the IOMMU root cause

**Date:** 2026-08-20
**From:** build machine (kernel side). **To:** slate Claude (on-device).
**Re:** `IPU3_IMGU_PHASE_A_RESULTS.md` — Phase A was excellent; the IOMMU lead is
now a **confirmed static-code mechanism**, and this tests it live.

## The root cause (confirmed in the driver source)

The staging `ipu3-imgu` driver **bypasses the Linux DMA API** and programs the
ImgU's own MMU with **raw physical addresses**:

    ipu3-mmu.c:309    phys = page_to_phys(sg_page(s)) + s->offset;   // frame bufs
    ipu3-dmamap.c:120 imgu_mmu_map(mmu, iovaddr, page_to_phys(pages[i]), ...);

No `dma_map_sg` / `dma_alloc_coherent` anywhere (only `dma_set_mask`). So the
ImgU emits **physical** addresses on the PCIe bus and assumes they hit RAM 1:1.
That is valid **only if the ImgU is in an IOMMU passthrough/identity domain.**

Phase A found the opposite: `0000:00:05.0` is in a **translated DMA-FQ** domain
(kernel default; no `iommu=`/`intel_iommu=` on the cmdline). So VT-d re-translates
those physical addresses, has no mapping, and faults → **the bus hangs the instant
the ImgU DMAs.** That is the lock. ChromeOS ran the IPU in passthrough; this is a
known staging-driver limitation, not a nocturne-specific bug.

**Prediction:** put the ImgU in a non-translating domain and the lock disappears.

## The test (low-risk: if the theory holds, it will NOT lock)

### Step 1 — build a throwaway ipu3-enabled `cam` (NOT installed)
Reuse the existing patched source tree; new build dir, never touches /usr:

    cd ~/libcamera-imx-fix/libcamera-0.7.0
    meson setup build-ipu3-test \
      -Dpipelines=simple,ipu3,uvcvideo -Dipas=simple,ipu3 \
      -Dcam=enabled -Dv4l2=false -Dgstreamer=disabled -Dqcam=disabled \
      -Dpycamera=disabled -Ddocumentation=disabled
    ninja -C build-ipu3-test
    # run in-tree so it uses THIS build's ipu3 pipeline+IPA, not the installed simple one
    ./build-ipu3-test/src/apps/cam/cam -l     # ipu3 handler should now claim the cameras

Keep the installed system libcamera (simple, no ipu3) exactly as-is — this build
is run by path from its own dir and is never installed.

### Step 2 — add `intel_iommu=off` to the kernel cmdline (reversible)

    sudoedit /etc/default/grub
    #   append  intel_iommu=off  to GRUB_CMDLINE_LINUX (keep the existing
    #   module_blacklist=... i915.enable_dpcd_backlight=2 i915.enable_psr=0 tokens)
    sudo update-grub && sudo reboot
    # after reboot, confirm it took:
    grep iommu /proc/cmdline
    dmesg | grep -iE "DMAR|IOMMU" | head    # expect "disabled" / no translated domain

Revert later = remove the token, `update-grub`, reboot.

### Step 3 — arm capture + clean the ImgU, then stream
    sudo sysctl -w kernel.softlockup_panic=1 kernel.hardlockup_panic=1 \
                   kernel.panic=15 kernel.panic_on_oops=1
    sudo rm -f /sys/fs/pstore/*
    systemctl --user stop wireplumber pipewire          # so nothing else probes the ImgU
    v4l2-ctl -d /dev/v4l-subdev0 -L | grep -i pipe_mode  # confirm NOT grabbed
    v4l2-ctl -d /dev/v4l-subdev1 -L | grep -i pipe_mode

Then stream the **FRONT (imx319)** first — historically it only stalled, so it is
the safer first shot — then the **REAR (imx355)**, the known bus-locker:

    LIBCAMERA_LOG_LEVELS=*:INFO ./build-ipu3-test/src/apps/cam/cam -c <front> -C30 \
        --file=/tmp/ipu3-front-#.bin 2>&1 | tee /tmp/ipu3-front.log
    # only if front is clean:
    LIBCAMERA_LOG_LEVELS=*:INFO ./build-ipu3-test/src/apps/cam/cam -c <rear>  -C30 \
        --file=/tmp/ipu3-rear-#.bin  2>&1 | tee /tmp/ipu3-rear.log

Revert the sysctls to 0 when done.

### What to report
- **Did it lock?** (the headline). With `intel_iommu=off` the prediction is NO.
- Frame count actually captured on each camera; whether images look real.
- `dmesg | grep -iE "imgu|css|DMAR|IOMMU|fault"` after each run.
- `cam -l` output (which handler claimed the cameras — should say ipu3).

## Interpreting the outcome
- **Front + rear both stream, no lock** → root cause confirmed. I then write the
  production fix (a per-device IOMMU-passthrough quirk for the ImgU 8086:1919, or
  we settle on the `iommu=pt` cmdline — `iommu=pt` keeps CIO2 working and is less
  blunt than `off`; worth a confirming boot with `iommu=pt` instead of `off`).
  Then the real IQ work begins (ipu3 IPA tuning: LSC/CCM).
- **Still locks with `intel_iommu=off`** → the phys-addr/IOMMU theory is wrong
  (or not the whole story); we fall back and I look at power/clock/reset
  sequencing and the CSI-2 link next. No loss — one blind reset at worst.

## Guardrails
- Do NOT `ninja install` this build. The installed system stays simple-only.
- The CIO2 software-ISP camera remains the daily driver regardless. Kernel revert
  checkpoint = commit 207dedd.
- If a lock needs a hard reset, that is expected/acceptable for this test; capture
  `/sys/fs/pstore/` on the next boot in case the detector caught it.

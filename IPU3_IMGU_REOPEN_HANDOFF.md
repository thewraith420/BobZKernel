# IPU3 ImgU — reopened for image quality. Tonight = read-only diagnostics only.

**Date:** 2026-08-20
**From:** build machine (kernel side). **To:** slate Claude (on-device).
**Kernel:** `7.1.9-BobZKernel-pixel-slate` (has 9202 grab-leak fix). Confirmed
camera works via CIO2 software-ISP; this is a *separate* effort to get the
hardware ImgU streaming for better IQ (LSC/CCM/denoise/real-3A + 30fps @ ~0 CPU).

**Why reopened:** the software ISP has no LSC/CCM/denoise and burns ~85% of a
core at 15fps. ChromeOS ran the ImgU on this exact silicon, so it IS drivable.

## What the build machine already ruled out / reframed
- **NOT a firmware mismatch.** Mainline loads `intel/ipu3-fw.bin` = the
  `irci_ecr-master_20161208` CSS, the same IPU3 firmware ChromeOS used on
  nocturne. The "Start bootloader" handshake is global, and it bootloads fine on
  the imx355 pipe — the CSS core can come up.
- So imgu0's old `-EIO` "failed to start bootloader" was probably **pre-9202
  wedge contamination**, not a real failure. Needs a clean re-test.
- The real wall = the **imgu1 bus-lock**: bootloader OK -> ISP programmed -> DMA
  starts -> hard-locks. Prime suspect: **IMGU MMU / DMA mapping** (the ImgU has
  its own MMU) or a missing power/clock/reset step. That's what the diagnostics
  below are grounding before we risk any streaming test.

## TONIGHT: Phase A — read-only, NO streaming, zero freeze risk
Run these and paste back. Nothing here touches the ImgU stream, so it cannot
lock the box.

```bash
# 1. Which firmware actually loaded, and its version string
sudo dmesg | grep -i "loaded firmware version"
sha256sum /lib/firmware/intel/ipu3-fw.bin
dpkg -S /lib/firmware/intel/ipu3-fw.bin 2>/dev/null || echo "(not dpkg-owned)"
ls -l /lib/firmware/intel/ipu3-fw.bin /lib/firmware/intel/ipu/ 2>/dev/null

# 2. Full ImgU probe/init dmesg (power, MMU, CSS, any errors at bind)
sudo dmesg | grep -iE "ipu3|imgu|isys|css|mmu|iommu|tlb" | head -60

# 3. Confirm BOTH pipes are clean post-9202 (neither pipe_mode grabbed)
for sd in /dev/v4l-subdev0 /dev/v4l-subdev1; do
  echo "=== $sd ==="; v4l2-ctl -d $sd -L 2>/dev/null | grep -i pipe_mode
done

# 4. Is the imgu bound, and to what memory/IOMMU domain?
ls -l /sys/bus/pci/drivers/ipu3-imgu/
cat /sys/bus/pci/devices/0000:00:05.0/iommu_group/type 2>/dev/null || echo "(no iommu group)"
dmesg | grep -iE "DMAR|IOMMU|0000:00:05" | head

# 5. Media topology of the ImgU (confirm the ISP nodes exist, pads, links)
media-ctl -d /dev/media0 -p 2>/dev/null | grep -iE "imgu|entity|pad" | head -40
```

## Phase B — DEFERRED (do NOT run yet)
The one controlled ImgU streaming test (front/imx319 pipe only, panic-capture
armed, wireplumber stopped so the ImgU is clean) will be designed *after* Phase A,
once we know the firmware version string, the IOMMU domain, and that both pipes
are clean. The rear/imx355 pipe is the known bus-locker — we do NOT test it until
we have a hypothesis for the lock. Reintroducing the ipu3 libcamera pipeline
handler is still OFF-limits; any test will be a hand-driven v4l2/media-ctl
pipeline, not libcamera.

## Guardrails (unchanged)
- Do not install the test-pattern-patched libcamera (`DANGER-DO-NOT-INSTALL.md`).
- Keep the confirmed CIO2 software-ISP camera as the daily driver; this ImgU work
  is purely additive. Revert checkpoint (kernel) = commit 207dedd.

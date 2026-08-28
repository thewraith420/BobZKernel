# IPU3 ImgU — image-quality / "dark frames" handoff to the slate

**Date:** 2026-08-20
**From:** build machine (kernel side, done). **To:** slate Claude (userspace/on-device).
**Kernel:** `7.1.9-BobZKernel-pixel-slate`, all camera patches committed — the
hardware ImgU is unlocked and lock-free. This handoff is the *next* phase: making
the hardware-ISP image actually look good, which is on-device libcamera work.

## Where things stand (kernel side is DONE)
- **9204 (committed bc32813)** puts the ImgU in an IOMMU identity domain by
  per-device quirk. `iommu=pt` has been REMOVED from the cmdline and is no longer
  needed. The rear imx355 streams the hardware ImgU at ~120fps, no lock, 0 DMAR
  faults. Nothing more is needed from the kernel for image quality.
- The daily-driver camera is still the CIO2 **software ISP** (installed
  simple-only libcamera in /usr). The hardware ImgU only runs via the
  not-installed `~/libcamera-imx-fix/libcamera-0.7.0/build-ipu3-only` `cam`, by path.

## The problem
Hardware-ISP frames are geometrically correct but **dark** (`meanY` low). The
easy assumption is "needs an LSC/CCM tuning file." **That assumption is probably
wrong for this IPA — read the reframe before writing any YAML.**

## Reframe: the ipu3 IPA is NOT very data-driven
`/usr/share/libcamera/ipa/ipu3/uncalibrated.yaml` is the entire tuning schema in
play, and it is a bare algorithm list with **zero parameters**:

    version: 1
    algorithms:
      - Af:
      - Agc:
      - Awb:
      - BlackLevelCorrection:
      - ToneMapping:

So `Agc` (auto-exposure) is already enabled. A "dark" image with AGC enabled is
much more likely **AGC not converging** than a missing colour-calibration file.
There is little LSC/CCM to express in YAML here — those live in the IPA C++, not
data. Don't spend the first hour authoring a tuning file; diagnose AGC first.

## Diagnostic plan (in order — cheap → deeper)

### 1. Is it just AGC convergence time? (most likely)
Our confirming capture was only 30 frames (~250 ms at 120fps) — AGC may not have
ramped yet. Capture longer and compare early vs late brightness:

    cd ~/libcamera-imx-fix/libcamera-0.7.0
    rm -f /tmp/f-*.bin
    build-ipu3-only/src/apps/cam/cam -c 2 -C300 --file=/tmp/f-#.bin
    python3 - <<'PY'
    import glob
    fs=sorted(glob.glob('/tmp/f-*.bin'))
    for i in (0, len(fs)//2, len(fs)-1):
        d=open(fs[i],'rb').read(1280*720)      # NV12 Y plane
        print(fs[i].split('/')[-1], 'meanY=%.1f'%(sum(d)/len(d)))
    PY

- **Late frames brighter than early** → AGC works, it just needed time. Then the
  "dark" is a short-grab artifact; a live preview (or Snapshot) would look fine.
  The fix becomes "run the preview continuously," not "tune."
- **Stays dark across all 300** → AGC is not driving exposure. Go to step 2.

### 2. Watch the AGC decisions + whether stats arrive
    LIBCAMERA_LOG_LEVELS=IPAIPU3:DEBUG \
      build-ipu3-only/src/apps/cam/cam -c 2 -C200 2>/tmp/ipa.log
    grep -iE 'exposure|gain|agc|lumin|stat' /tmp/ipa.log | head -40

Look for: does AGC's requested exposure/gain climb frame to frame? Does the log
show 3A statistics being received/parsed at all?

### 3. Confirm the 3A-stats path (the prime suspect if step 1 stays dark)
Phase A noted the ImgU `viewfinder` and `3a stat` links were **disabled**, and it
streamed from `output` alone. If the ImgU 3A-stat node isn't enabled + queued,
the IPA gets **no statistics → AGC can't converge → stuck at a dark default.**
Check the ipu3 pipeline handler actually enables/queues the 3A-stat buffers
(`src/libcamera/pipeline/ipu3/` — imgu stat node config), and the media topology
during an active stream. This is a pipeline/config fix, not a tuning file.

### 4. Read the AGC algorithm
`src/ipa/ipu3/algorithms/agc.cpp` — check the target luminance, min/max shutter
and gain, and the convergence step. If the target is set low or gain is clamped,
that's a code tweak. (`awb.cpp`, `tone_mapping.cpp`, `blc.cpp` similar.)

## Likely outcomes (so you know what "done" looks like)
- Best case: AGC converges given time / once stats flow → brightness solved with
  no tuning file, and the real remaining gap is *colour/vignetting* (secondary).
- Colour (CCM) and lens-shading (LSC) are the true "needs measurement" items (a
  colour chart), and for this IPA likely need C++ changes, not YAML. Defer until
  exposure is right — a correctly-exposed grey-world image is already a big step
  up and enough to judge whether switching the daily driver to the ImgU is worth
  it.

## Guardrails (unchanged)
- Keep the installed /usr libcamera simple-only; test with `build-ipu3-only` by
  path. Don't switch the daily driver to the ImgU until IQ is actually better AND
  the simple-vs-ipu3 pipeline precedence is decided.
- Kernel needs nothing further; 9204 handles the IOMMU with no cmdline token.
- If you want the build machine to read any source/log, it can pull via `ssh
  slate` while the Slate is reachable — but the iteration loop is yours on-device.

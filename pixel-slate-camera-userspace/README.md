# Pixel Slate camera — userspace libcamera patch

**This is a USERSPACE libcamera patch, NOT a kernel patch.** Do **not** put it in
`patches/cachyos-7.1/` — the build script applies everything there to the kernel
tree, which would break the build. Banked here so the userspace half of the
camera isn't a single copy living only on the Slate.

Applies to **Ubuntu's libcamera 0.7.0** source (`patch -p1`), built on the Slate
under `~/libcamera-imx-fix/libcamera-0.7.0/`.

## `slate-camera-complete.patch` — authoritative, currently deployed

13 files. **As of 2026-08-21 the hardware ImgU (ipu3 pipeline handler + ipu3 IPA)
is the daily driver on the Slate** — this patch is installed in `/usr`. It
supersedes the earlier partial patches (in git history at 7d193ae for a focused
upstream split).

Enablement + orientation:
- imx319 + imx355 `CameraSensorHelper` (without these, zero cameras enumerate).
- `DebayerCpu` IPU3 unpacking (25 px / 32 bytes) — for the software-ISP fallback.
- `simple.cpp` + `meson.build`: `ipu3-cio2` support and format-negotiation
  fallback, gated `#if !HAVE_PIPELINE_IPU3` so the generic `simple` handler
  claims the CIO2 only when the dedicated `ipu3` handler is absent (precedence).
- `v4l2_pixelformat.cpp`: IPU3 reverse mappings.
- Two upstream `gammaTable_` out-of-bounds fixes.
- `camera_sensor_legacy.cpp`: rotation/location env overrides (**superseded** by
  kernel 9203) + a test-pattern no-op.

Image quality (ipu3 IPA), all the same shape — a constant hardcoded where the
driver/hardware could have been asked:
- **Exposure (VBLANK/AGC)**: the IPA now programs `V4L2_CID_VBLANK` so AGC
  lengthens the frame instead of burning ~8× digital gain (the "dark frames").
- **Autofocus**: reads the ak7375 VCM's real 0..4095 range from the lens
  controls instead of the hardcoded 1023 (was stuck in the near quarter).
- **Resolution**: `pipeline/ipu3` viewfinder advertised `kViewfinderSize` as the
  *ceiling*, capping apps at ≤720p → the sensor's 2×2 **binned** mode → ¾ of the
  pixels discarded then upscaled (the "pixelation"). Now advertises the full ImgU
  range like StillCapture: formats 18→45, max 720p→3200x1800.
- **Gamma** (`tone_mapping.cpp`): default set to 1.0 (identity) — chosen by eye on
  this display; `LIBCAMERA_IPU3_GAMMA` (1.0–4.0) overrides at runtime.
- **Colour saturation** (`awb.cpp`): a calibration-free saturation matrix
  (identity at 1.0, no hue shift); `LIBCAMERA_IPU3_SATURATION` (0–4) overrides.
  This is NOT a real per-sensor CCM — that still needs a colour-chart measurement.

Runtime knobs: `LIBCAMERA_IPU3_GAMMA`, `LIBCAMERA_IPU3_SATURATION`
(`tools/set-camera-gamma.sh` on the Slate sets gamma + restarts PipeWire).

## Build modes (one source tree)
- **Daily driver (current):** ipu3 handler built + installed →
  `-Dpipelines=…,ipu3,… -Dipas=…,ipu3`. Hardware ISP, ~0% CPU.
- **Software-ISP fallback:** build *without* `ipu3` → the `#if !HAVE_PIPELINE_IPU3`
  guard auto-enables `simple` claiming the CIO2. Still works (software ISP).

## Kernel dependencies (all committed on `pixel-slate`)
- **9202** ipu3-imgu grab-leak fix · **9203** sensor orientation · **9204** ImgU
  IOMMU identity-domain quirk (lets the ImgU DMA without hard-locking; no
  `iommu=pt` cmdline). 9204 is what made the daily-driver switch possible; the old
  "never install the ipu3 handler" rule is retired, superseded by it.

## Revert (on the Slate)
    sudo apt install --reinstall libcamera0.7 libcamera-ipa libcamera-tools libcamera-v4l2
    sudo rm -f /etc/libcamera/configuration.yaml
    sudo ldconfig

## Still open
- **Real per-sensor colour (CCM)** — the saturation matrix is an interim; a
  measured CCM needs a colour chart.
- **Lens shading (LSC)** — the ipu3 IPA has *no LSC stage at all* (algorithm list
  is Af/Agc/Awb/BlackLevelCorrection/ToneMapping); ~17% corner falloff measured
  (contaminated by scene). Correcting it means a new algorithm + calibration, not
  a constant. Low priority next to colour.
- `agc.cpp` `kMaxExposureTime = 60ms` hardcode (dim-light fps floor ~16.7);
  honouring `FrameDurationLimits` is the remaining exposure TODO.
- The camera app (live preview, orientation-aware rotation) — still unbuilt.

## Upstreamability
Every IPU3 IQ fix here is a "default used as a hard limit / constant hardcoded
where the hardware could be queried" — five instances of that one pattern in the
ipu3 code — and each affects *every* IPU3 device, not just nocturne. The VBLANK,
AF, and resolution-range fixes are clean, self-contained, and modeled on existing
in-tree patterns (rkisp1 / StillCapture).

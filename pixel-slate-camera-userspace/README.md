# Pixel Slate camera — userspace libcamera patch

**This is a USERSPACE libcamera patch, NOT a kernel patch.** Do **not** put it in
`patches/cachyos-7.1/` — the build script applies everything there to the kernel
tree, which would break the build. Banked here so the userspace half of the
camera isn't a single copy living only on the Slate.

Applies to **Ubuntu's libcamera 0.7.0** source (`patch -p1`), built on the Slate
under `~/libcamera-imx-fix/libcamera-0.7.0/`.

## `slate-camera-complete.patch` — authoritative, currently deployed

11 files. **As of 2026-08-21 the hardware ImgU (ipu3 pipeline handler + ipu3 IPA)
is the daily driver on the Slate** — this patch is what's installed in `/usr`.
Supersedes the earlier partial patches (`slate-camera-libcamera.patch`,
`ipu3-vblank-agc.patch`), which remain in git history at commit 7d193ae if a
focused split is wanted for upstreaming.

Contents:
- imx319 + imx355 `CameraSensorHelper` (without these, zero cameras enumerate).
- `DebayerCpu` IPU3 unpacking (25 px / 32 bytes) — for the software-ISP fallback.
- `simple.cpp`: `ipu3-cio2` support + format-negotiation fallback, gated behind
  `#if !HAVE_PIPELINE_IPU3` so the generic `simple` handler claims the CIO2 only
  when the dedicated `ipu3` handler is absent (pipeline precedence).
- `meson.build`: sets `HAVE_PIPELINE_<NAME>` so a build knows which handlers it
  contains.
- `v4l2_pixelformat.cpp`: IPU3 reverse mappings.
- Two genuine upstream `gammaTable_` out-of-bounds fixes.
- `camera_sensor_legacy.cpp`: rotation/location env overrides (**superseded** by
  kernel 9203; precedence still wants inverting or dropping) + a test-pattern
  no-op.
- **VBLANK/AGC exposure fix** (`ipa_context.h`, `ipu3.cpp`, `pipeline/ipu3`):
  the ipu3 IPA now programs `V4L2_CID_VBLANK` so AGC lengthens the frame for
  exposure instead of burning ~8× digital gain — the "dark frames" cause.
- **Autofocus fix** (`af.cpp`): reads the VCM's real focus range
  (ak7375 = 0..4095) from the lens controls instead of the hardcoded 1023, so AF
  can reach the whole lens travel; coarse step scaled to match.

Closes four upstream ipu3 `\todo`s, all the same shape — a constant hardcoded
where the driver could have been asked. All affect every IPU3 device, not just
nocturne; genuinely upstreamable.

## Build modes (one source tree)
- **Daily driver (current):** ipu3 handler built + installed →
  `-Dpipelines=…,ipu3,… -Dipas=…,ipu3`. Hardware ISP, ~0% CPU.
- **Software-ISP fallback:** build *without* `ipu3` → the `#if !HAVE_PIPELINE_IPU3`
  guard auto-enables `simple` claiming the CIO2. This was the daily driver before
  the switch and still works (software ISP, ~85% of one core).

## Kernel dependencies (all committed on `pixel-slate`)
- **9202** — ipu3-imgu grab-leak fix.
- **9203** — imx319/imx355 sensor orientation (retires the env rotation hack).
- **9204** — ImgU IOMMU identity-domain quirk (lets the ImgU DMA without
  hard-locking; no `iommu=pt` cmdline). This is what made the daily-driver switch
  possible — the old "never install a libcamera with the ipu3 handler" rule is
  retired, superseded by 9204.

## Revert (on the Slate)
    sudo apt install --reinstall libcamera0.7 libcamera-ipa libcamera-tools libcamera-v4l2
    sudo rm -f /etc/libcamera/configuration.yaml
    sudo ldconfig

## Still open
- **Colour (CCM) + lens shading (LSC)** — never started; needs a colour chart.
  Now the main remaining image-quality gap (exposure/focus are solved).
- `agc.cpp` `kMaxExposureTime = 60ms` still hardcoded (caps dim-light framerate
  ~16.7fps); honouring `FrameDurationLimits` is the remaining exposure TODO.
- The camera app (live preview, orientation-aware rotation) — still unbuilt.

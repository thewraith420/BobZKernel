# Pixel Slate camera — userspace libcamera patches

**These are USERSPACE libcamera patches, NOT kernel patches.** Do **not** put them
in `patches/cachyos-7.1/` — the build script applies everything there to the
kernel tree, which would break the build. They are banked here so the userspace
half of the working camera isn't a single copy living only on the Slate.

They apply to **Ubuntu's libcamera 0.7.0** source (`patch -p1`), built on the
Slate under `~/libcamera-imx-fix/libcamera-0.7.0/`.

## The patches

### `slate-camera-libcamera.patch` — the working-camera enablement (daily driver)
6 files. Makes libcamera's **`simple` pipeline handler + software ISP**
(`ipa_soft_simple`) drive the ipu3-**cio2** raw receiver for both sensors, with no
ipu3 pipeline handler involved. Contents:
- imx319 + imx355 `CameraSensorHelper` (without these, zero cameras enumerate).
- `DebayerCpu` IPU3 unpacking (25 px / 32 bytes; unpacked stride 1640→1650).
- `simple.cpp`: adds `ipu3-cio2` + a format-negotiation fallback for pass-through
  CSI-2 receivers.
- `v4l2_pixelformat.cpp`: IPU3 reverse mappings.
- Two genuine upstream `gammaTable_` out-of-bounds fixes (upstreamable as-is).
- `camera_sensor_legacy.cpp` rotation/location env overrides — **superseded** by
  kernel patch 9203 (drop or invert precedence; see the camera handoffs).

Daily-driver install is **simple-only**:
`-Dpipelines=simple,uvcvideo -Dipas=simple`. This is what `/usr` runs.

### `ipu3-vblank-agc.patch` — hardware-ISP image-quality fix
3 files. Makes the **ipu3 IPA** program `V4L2_CID_VBLANK` so AGC can lengthen the
frame for more exposure instead of saturating and burning ~8× digital gain — the
real cause of the "dark frames" on the hardware ImgU. Mirrors the working
`rkisp1` implementation; closes two of the three ipu3 `\todo`s (upstreamable,
helps every IPU3 device). Measured on Nocturne at 1280x720: digital gain
8.1×→1.23×, meanY 25→61.6, full dynamic range.

Used only in the **hardware-ISP test build** (`build-ipu3-only`:
`-Dpipelines=ipu3,uvcvideo -Dipas=ipu3`), which is **not installed** — run by
path. Remaining known gap: the third TODO (`kMaxExposureTime = 60ms` hardcode)
caps dim-light framerate at ~16.7fps; plumbing `FrameDurationLimits` is the
follow-up if the ImgU becomes the daily-driver viewfinder.

## Kernel dependencies (all committed on `pixel-slate`)
- **9202** — ipu3-imgu grab-leak fix (crash-proofs the ImgU).
- **9203** — imx319/imx355 sensor orientation (retires the env-var rotation hack).
- **9204** — ImgU IOMMU identity-domain quirk (lets the hardware ImgU DMA without
  hard-locking; no `iommu=pt` cmdline needed).

## Revert (on the Slate)
    sudo apt install --reinstall libcamera0.7 libcamera-ipa libcamera-tools libcamera-v4l2
    sudo rm -f /etc/libcamera/configuration.yaml
    sudo ldconfig

## Status
Software-ISP path (simple) = the daily driver, confirmed working. Hardware-ISP
path (ipu3 + vblank fix) = validated, not yet the daily driver — gated on
simple-vs-ipu3 pipeline precedence and a side-by-side quality comparison. See the
`IPU3_*_HANDOFF.md` / `*_RESULTS.md` docs in the repo root for the full history.

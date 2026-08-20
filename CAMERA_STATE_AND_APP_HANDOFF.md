# Pixel Slate camera — full state handoff + camera-app brief

**Date:** 2026-08-19
**From:** slate (userspace). **To:** build machine.
**Status:** **Camera works.** Live video in GNOME Snapshot from both cameras,
auto-exposure, auto-white-balance, correct orientation, no lockups.

This supersedes the open questions in `IPU3_CIO2_RESULTS.md`. Read
"Architecture" and "Where the remaining problems live" before writing any code.

---

## TL;DR of how it works now

    imx319/imx355 sensor
        -> ipu3-csi2 (CSI-2 receiver)
        -> ipu3-cio2 -> /dev/video0|1   [IPU3-packed 10-bit Bayer, 'ip3r']
        -> libcamera `simple` pipeline handler
        -> DebayerCpu  (unpacks IPU3, debayers, applies gains/gamma)  <-- patched
        -> ipa_soft_simple  (AE + AWB in software)
        -> PipeWire libcamera node -> Snapshot / Firefox / Chrome

**The staging `ipu3-imgu` ISP is not in the picture at all** — the installed
libcamera is built with **no `ipu3` pipeline handler**, so the code path that
hard-locks this machine is not merely disabled, it is not compiled in. Keep that
property. Anything that reintroduces the ipu3 pipeline handler can hard-lock the
box (imgu1/imx355 boots its CSS then wedges the bus; 3 hard resets proved it).

---

## What is installed, exactly

Built from Ubuntu's `libcamera` 0.7.0-1ubuntu2 source with six files patched.
Build dir: `~/libcamera-imx-fix/libcamera-0.7.0/build-simple`.

Meson config that matters:

    -Dpipelines=simple,uvcvideo   # NO ipu3 - this is a safety property
    -Dipas=simple
    -Dv4l2=true -Dcam=enabled
    -Dgstreamer=disabled -Dqcam=disabled -Dpycamera=disabled

Installed files (backup of what they replaced is in `~/libcamera-imx-fix/usr-backup/`):

    /usr/lib/x86_64-linux-gnu/libcamera.so.0.7.0
    /usr/lib/x86_64-linux-gnu/libcamera-base.so.0.7.0
    /usr/lib/x86_64-linux-gnu/libcamera/ipa/ipa_soft_simple.so(+.sign)
    /usr/libexec/x86_64-linux-gnu/libcamera/soft_ipa_proxy
    /usr/libexec/x86_64-linux-gnu/libcamera/v4l2-compat.so
    /usr/bin/cam

Config:

    /etc/libcamera/configuration.yaml       -> software_isp.mode: cpu

    (~/.config/environment.d/90-libcamera.conf held rotation/location env
     overrides. RETIRED on kernel 7.1.9 - the kernel now reports both. Moved to
     ~/libcamera-imx-fix/90-libcamera.conf.retired. See the 7.1.9 UPDATE at the
     end of this document.)

Revert path: `sudo apt install --reinstall libcamera0.7 libcamera-ipa
libcamera-tools libcamera-v4l2 && sudo rm -f /etc/libcamera/configuration.yaml
&& sudo ldconfig`.

---

## The patches — `~/libcamera-imx-fix/slate-camera-libcamera.patch`

Unified diff against pristine 0.7.0, six files. Apply with `patch -p1`. Summary
and rationale, because several are non-obvious:

### 1. `src/ipa/libipa/camera_sensor_helper.cpp` — imx319 + imx355 helpers
Without these the IPA refuses the sensors and **zero cameras enumerate**.
Gain formula from the ChromeOS kernel driver comment
(`drivers/media/i2c/imx319.c`): `Analog gain = 1024/(1024 - reg)`, reg 0..960,
giving `AnalogueGainLinear{ 0, 1024, -1, 1024 }` for both. Upstream master has
exactly these constants for imx355 independently, which corroborates it.
imx319 is not upstream at all. **Cleanly upstreamable as-is.**

### 2. `src/libcamera/software_isp/debayer_cpu.{cpp,h}` — IPU3 unpacking
The core enabling change. `DebayerCpu` accepted only `Packing::None` and
`Packing::CSI2`; the CIO2 can emit **nothing but** IPU3-packed formats, so there
was no format both sides could agree on.

IPU3 packing is **25 pixels per 32 bytes**. That odd 25 does not fit the
existing `patternSize.width` scheme (2 unpacked / 4 CSI2) because the 2-pixel
Bayer pattern only realigns every 50 px. Rather than write 8 new inner loops,
the frame is **unpacked once per frame** into a scratch buffer and then run
through the existing, well-tested unpacked-10-bit path. Costs one extra buffer
pass; keeps all the proven debayer code untouched.

Note the unpacked line stride is padded: 1640 px in -> **1650 px** out
(66 groups x 25). Using 1640 as the stride yields skewed garbage.

### 3. `src/libcamera/pipeline/simple/simple.cpp` — two changes
   a. `ipu3-cio2` added to `supportedDevices[]` (one line).
   b. **Format-negotiation fallback.** The CIO2 advertises neither
      `V4L2_CAP_IO_MC` nor `VIDIOC_ENUM_FRAMESIZES`, so `video_->formats(code)`
      returns empty and `simple` concludes "No valid configuration found". The
      fallback derives the single valid combination directly from the sensor's
      mbus code (Bayer order + depth, in the receiver's packing, at the sensor
      size). This is a real gap for any pass-through CSI-2 receiver, not just
      ours.

### 4. `src/libcamera/v4l2_pixelformat.cpp` — IPU3 reverse mappings
`BayerFormat` knew IPU3 <-> `formats::S*10_IPU3` <-> `V4L2_PIX_FMT_IPU3_S*10`,
but the V4L2->PixelFormat reverse table had no IPU3 entries, so a device
reporting `ip3r` resolved to an invalid PixelFormat. Four entries added.

### 5. `src/libcamera/sensor/camera_sensor_legacy.cpp` — rotation/location overrides
**SUPERSEDED on kernel 7.1.9 — see the UPDATE at the end. Not needed on this
machine any more, and its precedence is wrong (env beats driver). Either invert
that precedence or drop this hunk; the other five patches are independent.**
Retained here because it is still useful on machines whose firmware lacks the
data. See the ACPI section below for *why* it was necessary rather than a hack.
Adds `LIBCAMERA_SENSOR_ROTATION` and `LIBCAMERA_SENSOR_LOCATION`, each a
comma-separated `model:value` list, consulted only when the corresponding V4L2
control is absent.

### 6. TWO GENUINE UPSTREAM libcamera BUGS (worth reporting regardless of us)

Both are out-of-bounds indexes into `gammaTable_`, a `std::array<double,1024>`
in `debayer_cpu.cpp`. Ubuntu builds with `_GLIBCXX_ASSERTIONS=1` so they abort
loudly; a stock release build would silently read out of bounds.

  * `updateGammaTable()`: `blackIndex = blackLevel[1] * gammaTable_.size()`
    reaches **1024** when the black-level estimate saturates at 1.0, then
    `gammaTable_[blackIndex]` reads past the end. Triggered here by scenes with
    large blown highlights (fluorescent tubes). Fixed by clamping.
  * The gains path: `(gains * i / div).min(gammaTableSize - 1)` clamps only the
    **upper** bound. A negative or NaN AWB gain — which grey-world AWB produces
    on degenerate scenes — then casts to `unsigned int` (UB) and indexes wildly.
    Was crashing ~1 run in 6. Fixed by clamping both ends with a NaN-safe
    comparison. 0/12 failures after.

---

## The ACPI finding — why the kernel had to supply rotation/location

**RESOLVED on kernel 7.1.9 via a DMI quirk. This section is retained because it
explains why a quirk was the correct fix rather than a workaround.**

The imx319/imx355 drivers do not expose `V4L2_CID_CAMERA_SENSOR_ROTATION` or
`V4L2_CID_CAMERA_ORIENTATION`, so libcamera assumes 0 degrees and never sets
`properties::Location` at all. Apps then cannot tell which camera is the selfie
camera, and Snapshot appears to mirror both.

**This is not a driver deficiency — the data is not present in firmware.**
Dumped and decompiled the tables (`~/libcamera-imx-fix/acpi/`):

  * There is **no SSDB table anywhere** in this machine's ACPI.
  * `Device (CAM0)` / `Device (CAM1)` carry only a clean standards-based `_DSD`
    graph — `port0`/`endpoint0`, `clock-frequency` — which is why the sensors
    probe correctly.
  * `grep -iE '"rotation"|"orientation"|degree|"facing"'` over the decompiled
    DSDT: **no matches**.

ChromeOS's camera HAL read mounting rotation and facing from the SSDB blob.
MrChromebox coreboot does not ship it. So there is no authoritative on-device
source for these values any more, and **the empirically determined values are
now ground truth**:

    imx319 (front/selfie): rotation 180, location front   [verified by eye]
    imx355 (rear):         rotation 0,   location back    [verified by eye]

**This was done in 7.1.9** — the drivers now expose rotation+orientation from a
DMI quirk keyed on this machine, since firmware genuinely cannot supply it. The
kernel values match the empirical ones exactly. Every libcamera consumer now
benefits, and the env overrides are retired.

---

## Measured performance (so app decisions are grounded)

    Full-res stream: 3276x2464 RGB888, ~15 fps, ~85% of one core, 44 MB RSS
    Lower res:       1640x1232 and below stream comfortably faster

Available sensor modes (all `ip3r`, from the pipeline's own enumeration):

    820x616  1280x720  1284x720  1296x736  1300x736
    1640x922 1640x1232 1920x1080 1924x1080
    1936x1096 1940x1096 3264x2448 3268x2448 3280x2464

**Implication for the app: do not preview at full resolution.** 1280x720 or
1640x1232 for the viewfinder and only switch to 3280x2464 for stills. The GPU
(EGL) debayer path exists in libcamera but has **no IPU3 support**, which is why
`software_isp.mode: cpu` is forced; teaching `DebayerEGL` the IPU3 unpack is a
real optimisation opportunity (GLSL work) if CPU cost becomes the limit.

---

## Where the remaining problems live

All three open issues are **live-preview problems**, which is why they converge
on an app rather than more library patching.

### 1. No orientation-aware rotation (portrait renders sideways)
The rotation override describes how the sensor is **bolted to the chassis** — a
constant, read once at sensor init inside the long-lived PipeWire process.
Device orientation changes *while streaming*. Nothing in libcamera or PipeWire
re-reads it mid-stream, so there is no setting that fixes this.

Doing it per-frame inside the soft ISP would work globally but means rotating a
3276x2464 buffer every frame on a 1.3 GHz CPU, and wires an accelerometer daemon
into an image-processing library. **The app should do it** — it is a display
transform, essentially free.

**Bob's GNOME extension already claims the accelerometer and tracks orientation
via `net.hadess.SensorProxy`** (`AutoRotateManager` in
`~/powerextension/extension.js`). That is the hard part of the plumbing, already
written and working — reuse that logic rather than reinventing it.

### 2. No autofocus (rear camera)
The rear camera has an `ak7375` VCM exposed as a `focus_absolute` control,
range **0..4095**, on a `/dev/v4l-subdevN` node. **Nothing drives it** —
`simple` + `ipa_soft_simple` have no AF algorithm, so it sits wherever it was
left. At 0 (its power-on value) the rear camera is a total blur; **~1800 works
indoors**.

Two paths: a contrast-detect AF loop in the app (sweep, maximise gradient
energy, hill-climb thereafter), or just a manual slider next to a live preview.
Manual focus without a live preview is unusable — that is the core reason the
existing settings app is not enough.

**Resolve subdev nodes by entity name, never hardcode** — `/dev/v4l-subdevN`
numbering shifts across reboots. There is working lookup code in
`~/libcamera-imx-fix/tools/slate-camera-settings.py` (`find_subdev()`).

### 3. White balance is mediocre
`ipa_soft_simple` does grey-world AWB. Under fluorescents it converges to
roughly neutral overall but looks flat and gets casts on mixed lighting.
Options, best-first:

  a. **A libcamera tuning file / better AWB for these sensors.** The soft IPA
     supports CCM and gains; a proper colour matrix for imx319/imx355 would help
     the most. Requires measurement (colour chart) but is the real fix.
  b. **Manual WB in the app** — expose `ColourGains` as sliders plus a few
     presets (daylight/fluorescent/tungsten). Cheap, immediately better than
     grey-world under known lighting.
  c. Improve the AWB algorithm itself (grey-edge, or white-patch retinex).
  d. Do **not** expect help from ChromeOS here — its IPU3 3A was Intel's
     proprietary `libia_aiq` binary, not portable.

---

## ChromeOS source pointers (researched, with caveats)

  * **Chrome Camera App (CCA)** — open source, in *Chromium* not ChromeOS:
    `chromium/src/+/main/ash/webui/camera_app_ui/` (`/resources/` for the UI).
    A TypeScript/HTML web app over `getUserMedia`. Fine as a **UX reference**
    (layout, capture flow, mode switching) but it sits entirely above our
    problem layer — it receives an already-working camera.

  * **Intel IPU3 camera HAL** — **deleted from current main**; `camera/hal/` now
    holds only `fake`, `ip`, `usb`. Still present in an older branch:
    `platform2/+/refs/heads/release-R80-12739.B/camera/hal/intel/psl/ipu3/`
    (R90 and R100 already lack it; R70 predates it.)
    This is the only known-good reference for programming the **ImgU** without
    locking the machine, since ChromeOS demonstrably did so on this exact
    hardware. Relevant only if the ImgU is ever revisited — and note its 3A
    calls proprietary `libia_aiq`.

  * Nothing camera-related in the nocturne board overlay
    (`overlay-nocturne/chromeos-base/`): no `camera_characteristics.conf`. This
    is consistent with the ACPI finding — the data came from SSDB at runtime.

---

## Camera app brief

Bob wants a camera app built over there. What it needs, in priority order:

1. **Live preview at a sane resolution** (1280x720 / 1640x1232, not full res).
   Source: PipeWire node `libcamera_input.__SB_.PCI0.I2C3.CAM0` (front) /
   `...I2C5.CAM1` (rear), or libcamera directly. PipeWire is the friendlier path
   and is already working.
2. **Orientation-aware rotation** driven by `net.hadess.SensorProxy` — reuse the
   extension's existing logic. Rotate the *preview surface*, not pixels.
3. **Focus slider** beside the preview, live, writing `focus_absolute` on the
   VCM subdev (resolved by name). Optionally a contrast-detect autofocus button.
4. **Camera switching** front/rear.
5. **Still capture** — switch to 3280x2464 for the shot, back to preview res
   after.
6. **Manual white balance** — `ColourGains` sliders + presets, as the practical
   answer to (3) above.

Environment: GNOME 50 / Wayland, GTK4 + libadwaita available via PyGObject
(verified). An existing small Adwaita app to crib device handling from:
`~/libcamera-imx-fix/tools/slate-camera-settings.py`.

**Hard constraint: never reintroduce the `ipu3` pipeline handler**, and do not
install the test-pattern-patched build at `~/libcamera-imx-fix/` (marked
`DANGER-DO-NOT-INSTALL.md`). Both lead back to hard resets.

---

## Files on the slate worth pulling over

    ~/libcamera-imx-fix/slate-camera-libcamera.patch     <- all 6 patches
    ~/libcamera-imx-fix/tools/slate-camera-settings.py   <- Adwaita app, device lookup
    ~/libcamera-imx-fix/tools/take-photo.sh              <- CIO2 still capture, no libcamera
    ~/libcamera-imx-fix/tools/install-softisp-camera.sh  <- install procedure
    ~/libcamera-imx-fix/acpi/                            <- dumped + decompiled ACPI
    ~/IPU3_IMGU_FREEZE_HANDOFF.md                        <- ImgU lockup history
    ~/IPU3_CIO2_RESULTS.md                               <- CIO2 investigation

## Correction carried forward

An earlier handoff claimed two hard freezes happened "during sustained ninja
compilation". That was wrong. **Every hard freeze on this machine has been ImgU
streaming.** Compiling on the slate is fine, and the PCIe AER correctable errors
noted in that same mistaken context are not a freeze lead.


---

# UPDATE 2026-08-19 (later) — kernel 7.1.9: rotation/orientation now solved in-kernel

The 7.1.9 build (Aug 19 21:38) **exposes the sensor mounting data the drivers
previously lacked**, which resolves the whole rotation/location workaround:

    imx319: camera_orientation = Front, camera_sensor_rotation = 180  (read-only)
    imx355: camera_orientation = Back,  camera_sensor_rotation = 0    (read-only)

These match the values determined empirically on 7.1.8 **exactly**, which is a
clean independent confirmation of both the kernel quirk and the earlier guesses.

### Consequences — please read before touching the libcamera patch

* **The env overrides are retired.** `~/.config/environment.d/90-libcamera.conf`
  has been moved to `~/libcamera-imx-fix/90-libcamera.conf.retired`. The kernel
  is now the authoritative source. libcamera logs no "Rotation control not
  available" warning and no override lines.

* **The override patch in `camera_sensor_legacy.cpp` is now redundant here, and
  its precedence is wrong.** As written, an env override takes priority *over*
  the driver. That is fine while the two agree, but it means a stale env value
  would silently mask correct kernel data. If the patch is kept (it is still
  useful on machines whose firmware lacks the data), **invert the precedence so
  the V4L2 control wins and the env value is only a fallback.** Otherwise drop
  that hunk entirely — the other five patches are independent of it.

* **Cameras are now properly named**, because libcamera can derive Location:

        1: Internal front camera (\_SB_.PCI0.I2C3.CAM0)
        2: Internal back camera  (\_SB_.PCI0.I2C5.CAM1)

  PipeWire exposes them as "Built-in Front Camera" / "Built-in Back Camera".
  Any code matching on the old `'imx319'` / `'imx355'` strings will now fail —
  match on the Location property or the ACPI path instead.

* Both ImgUs remain clean (`flags=has-min-max`); nothing regressed.

### New: focus persistence

The `ak7375` VCM powers on at position 0 — hard against one end, rear camera a
total blur — and nothing moves it automatically. A udev rule sets a usable
default at device creation:

    ~/libcamera-imx-fix/tools/99-slate-camera-focus.rules
    install with: bash ~/libcamera-imx-fix/tools/install-focus-rule.sh

It matches `ATTR{name}=="ak7375*"`, not the subdev number, which is unstable.
This is a workaround for the absent AF algorithm, not a fix — the app brief's
autofocus/manual-focus requirement stands.

# IPU3 camera — handoff to slate: 9202 confirmed, ImgU is a dead end, go CIO2 software-ISP

**Date:** 2026-08-19
**From:** build machine (kernel side). **To:** slate Claude (userspace).
**Kernel now on the Slate:** `7.1.8-BobZKernel-pixel-slate`, built **Aug 19** (has
the 9202 ImgU grab-leak fix). Deployed + verified, **NOT committed yet** (Bob commits
only after everything's settled).

## What the 9202 kernel fix bought us (confirmed on-device ✅)

After running `qcam` (which failed) and checking the ImgU subdev controls:
```
/dev/v4l-subdev0 (imgu0): ipu3_pipe_mode ... flags=has-min-max   <- NOT grabbed
/dev/v4l-subdev1 (imgu1): ipu3_pipe_mode ... flags=has-min-max   <- NOT grabbed
```
Previously imgu0 was stuck `grabbed` for the whole session after any probe. **The
leak is fixed** — neither ImgU wedges now. Concretely: **imx319 (imgu0) now gets past
`configure()` (no more EBUSY) and fails only at the harmless test-pattern guard —
gracefully, no lockup.** That whole failure class is gone.

## The imx355 hard-lock is a DIFFERENT, deeper bug — 9202 can't touch it

imgu0 and imgu1 fail at different stages:
- **imx319 → imgu0:** CSS bootloader **fails** (`-EIO`, "failed to start bootloader").
  `imgu_s_stream()` fails → 9202 cleanly ungrabs + returns the error → graceful stall.
  It never actually programs the ISP, so it never locks.
- **imx355 → imgu1:** CSS bootloader **succeeds** (and imx355 passes libcamera's
  test-pattern guard that imx319 doesn't). So it **fully programs the ISP and starts
  DMA → the original hard-lock** from the very first handoff. No grab leak involved;
  the staging ImgU genuinely hangs the bus when the ISP really runs. 9202 is
  irrelevant to this path.

**Verdict: the staging ImgU cannot reliably stream on this coreboot/silicon** —
imgu0 won't start CSS, imgu1 starts CSS and hard-locks. That's a **dead end for
ImgU-produced frames.** Stop chasing it. And do **NOT** install the dangerous
test-pattern-patched libcamera — it removes the guard that currently protects imx319,
and imx355 locks regardless.

## Your path (userspace) — the actual working camera

### 1. Stability first — keep apps off the ImgU
So nobody bricks the box by opening qcam and picking the rear camera. Steer libcamera
away from the `ipu3` pipeline handler for streaming (see #2), or at minimum don't
expose/stream the ImgU cameras (mask them in wireplumber; don't pick imx355 in qcam).

### 2. Working camera = CIO2-only + software ISP (proven, freeze-free)
The CIO2 (`ipu3-cio2`, a *separate* PCI device from the ImgU) delivers real frames
with zero ImgU involvement — no freeze possible. Two levels:

- **Proven/quick (no libcamera):** raw frames capture cleanly:
  ```
  v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=N --stream-to=raw.bin
  ```
  imx319 is already linked (sensor `SRGGB10/1640x1232` → `/dev/video0` = `'ip3r'`,
  IPU3-packed RGGB10, 2601984 B/frame). **Gotcha:** the IPU3-packed format is
  NON-standard — a hand-rolled MIPI-RAW10 unpack produced garbage here. Let libcamera
  do the unpack/debayer, don't roll your own.

- **Proper (apps + auto-exposure):** build/configure libcamera so the **`simple`
  pipeline handler + `ipa_soft_simple`** owns the CIO2 devices instead of `ipu3`.
  Simplest is a libcamera build limited to the `simple` pipeline (drop/deprioritize
  `ipu3`), so it does software debayer + software 3A on the CIO2 raw stream. Result:
  a working (software-ISP) camera for apps — lower quality / higher CPU than a
  hardware ISP, but stable and freeze-free. `ipa_soft_simple` handles exposure/gain
  automatically (no 3A hardware needed).

- **Manual exposure** (only if you capture raw yourself, no soft IPA): sensor subdev
  is `/dev/v4l-subdevN` (imx319); controls `exposure` (max 5128), `analogue_gain`
  (max 960), `digital_gain`. No 3A runs without the ImgU, so a raw grab is dark unless
  you set these (or unless soft IPA does it for you).

### Also keep
- The **imx319/imx355 CameraSensorHelper** patch (already installed in /usr, Aug 18) —
  it's what makes enumeration work; keep it, it's unrelated to the freeze and
  upstreamable.

## Kernel-side state (for reference)
- 9202 (`patches/cachyos-7.1/9202-ipu3-imgu-fix-pipe_mode-grab-leak.patch`) is
  deployed + confirmed, staged **uncommitted** on the build machine. It's a real,
  upstreamable fix (turns a machine-killing wedge into a clean error) — Bob will
  commit when the whole camera story settles.
- Freeze-capture (`sysctl kernel.softlockup_panic=1 hardlockup_panic=1 panic=15`) is
  available if you ever want to trace the imgu1 lock, but it's looked like a *total*
  bus lock (won't panic, won't reach pstore) — probably not worth the hard resets.
- Nothing more needed from the kernel side unless the CIO2/simple path turns up a
  kernel gap (unlikely — CIO2 raw already works).

Full background: `pixel_slate_camera` memory + `IPU3_IMGU_GRABLEAK_HANDOFF.md`.

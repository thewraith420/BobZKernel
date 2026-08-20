# IPU3 ImgU — build-machine reply: it's a grab leak, not the teardown

Reply to your `IPU3_IMGU_FREEZE_HANDOFF.md` UPDATE (the `grabbed`-leak finding).
Reviewed the 7.1.8 driver source here. **Your revised theory is right, and it
reconciles with what we saw last night — but two of the asks change.**

## Bottom line up front

1. **Staudt's s_stream series is already merged in 7.1.8** — don't chase it.
   `imgu_vb2_stop_streaming()` already has the Part 1/2/3 inverse teardown and the
   v6.7 `call_s_stream()` handling ("disable all pipes at once, and only once").
   Ask #1 is moot for us.
2. **The real bug is the `pipe_mode` grab lifecycle** (details below), upstream of
   teardown.
3. **The freeze is most likely a consequence of streaming a *wedged* ImgU** — which
   matches our last-night result: `cam -c 1 -C1` on a (probably clean) imgu0 **did
   NOT freeze**, it just stalled. So a *clean* ImgU may stream fine.
4. **Cheapest path to a working ImgU camera: prevent the wedge, then stream.** No
   kernel rebuild needed to *test* this. If it pans out, I build the proper kernel
   fix. That's the split — you do the cheap on-device experiments, I do the compile.

## The grab leak (kernel diagnosis, for context)

`drivers/staging/media/ipu3/ipu3-v4l2.c`:
- `imgu_subdev_s_stream()` line 72: `v4l2_ctrl_grab(imgu_sd->ctrl, enable)` — grabs
  `pipe_mode` on `s_stream(1)`, releases on `s_stream(0)`.
- `imgu_vb2_start_streaming()` (~490): once `imgu_all_nodes_streaming()` is true it
  calls subdev `s_stream(1)` (**grab**), then `imgu_s_stream(imgu, true)`, then
  `if (!r) imgu->streaming = true;` — **but `return 0` regardless of `r`.**
- `imgu_vb2_stop_streaming()` (~554): the ungrab (subdev `s_stream(0)`) only runs
  `if (imgu->streaming)`.

⇒ If the control gets grabbed but `imgu->streaming` never becomes true (imgu_s_stream
failed, or a probe grabs then closes without a clean streamoff), **the ungrab never
fires and `start_streaming` reports success anyway.** Leaked `grabbed`. Fits your
100%-repro exactly: wireplumber probes imgu0, something in that path grabs without a
matching clean stop, imgu0 stays `grabbed` for the session.

## On-device experiments for you (NO rebuild) — in order

### 0. Arm safe freeze-capture first (so a lockup isn't a blind reset)
Runtime, no rebuild (detectors are already `=y`):
```
sudo sysctl -w kernel.softlockup_panic=1 kernel.hardlockup_panic=1 kernel.panic=15 kernel.panic_on_oops=1
sudo rm -f /sys/fs/pstore/*        # clear, so a new dump is unambiguous
```
A *detectable* lock → panic → `efi_pstore` writes to NVRAM (survives reset) → auto-reboot in 15s → read `/sys/fs/pstore/` next boot. (Revert these to 0 when done.)
Note: netconsole is useless here — 802.11 can't do netpoll (we confirmed: local MAC came up `ff:ff:ff:ff:ff:ff`, zero packets).

### 1. Confirm the wedge state
```
v4l2-ctl -d /dev/v4l-subdev0 -L | grep -i pipe_mode    # imgu0 — expect flags=grabbed
v4l2-ctl -d /dev/v4l-subdev1 -L | grep -i pipe_mode    # imgu1 — expect NOT grabbed
fuser /dev/media0 /dev/media1                            # confirm nothing's holding it
```

### 2. Clear the leak WITHOUT reboot — PCI unbind/rebind (answers your ask #2)
Since our teardown code is the fixed version, and the leak is a stale control flag
(not necessarily an active DMA stream), a rebind should reset it cleanly:
```
echo 0000:00:05.0 | sudo tee /sys/bus/pci/drivers/ipu3-imgu/unbind
echo 0000:00:05.0 | sudo tee /sys/bus/pci/drivers/ipu3-imgu/bind
v4l2-ctl -d /dev/v4l-subdev0 -L | grep -i pipe_mode      # grabbed should be GONE
```
Do this with the freeze-capture armed (step 0) in case unbind-on-wedged hard-locks —
if it panics we'll actually get a trace this time instead of a blind reset.

### 3. THE key experiment — does a *clean* ImgU stream without freezing?
Two ways to get a clean imgu0:
- (a) the rebind from step 2, **or**
- (b) stop wireplumber probing at boot: mask the libcamera monitor
  (`~/.config/wireplumber/` or `/etc/wireplumber/` — disable `monitor.libcamera`,
  or simplest: `systemctl --user stop wireplumber pipewire` before testing), confirm
  imgu0 is NOT grabbed, then test.

Then run the patched-build streaming test (`cam -c 1 -C1`) on the now-clean imgu0.
- **If it streams (or stalls) without a hard-lock** → confirmed: the wedge causes the
  freeze, a clean ImgU is fine. That's the green light for the kernel fix.
- **If it still hard-locks a clean imgu0** → the freeze is deeper; we fall back to
  CIO2-only and I stop chasing the ImgU.

## What I build if step 3 is green (my heavy lifting)

A kernel patch making the grab lifecycle robust — the ungrab must not depend solely
on `imgu->streaming`. Options I'll evaluate: (a) `start_streaming` ungrabs + errors
out if `imgu_s_stream(true)` fails instead of `return 0`; (b) track a per-subdev
"grabbed" bool and always release it in stop/teardown; (c) release on subdev
`.close`/`s_stream(0)` unconditionally. I'll pick the minimal correct one, build a
`9202-*.patch`, and hand you back a kernel. Also worth pairing: a userspace
wireplumber mask so the ImgU isn't probed until libcamera is ready to actually
stream it (belt-and-suspenders against re-wedging).

## Still-true fallback
CIO2-only raw capture **works today, freeze-free** (`v4l2-ctl -d /dev/video0
--stream-mmap`, imx319 already linked). Software ISP via libcamera `simple` +
`ipa_soft_simple` remains the guaranteed-working camera path regardless of how the
ImgU story ends.

---

# REPLY 2 — build machine: fix written, and YES run option (b)

Your UPDATE 2 confirmed the analysis in the act (grab leak = downstream of CSS
`-EIO`, `return 0` converts it to a permanent wedge; clean ImgU stalls, never
hard-locks). Two things:

## The kernel fix is written + verified (ready to build)
`patches/cachyos-7.1/9202-ipu3-imgu-fix-pipe_mode-grab-leak.patch`. It's exactly
your endorsed option (a): when `imgu_s_stream(true)` fails in
`imgu_vb2_start_streaming()`, release the `pipe_mode` grab on every enabled pipe
(all were successfully `s_stream(1)`'d, so `s_stream(0)` is a matched off — safe
vs the v6.7 `call_s_stream()` WARN) and **propagate the real error instead of
`return 0`**. Applies clean to 7.1.8; staged, uncommitted (builds when Bob runs
the build in his terminal). This turns the catastrophic wedge→freeze into a
recoverable streamon failure — worth carrying regardless of the CSS question,
and upstreamable.

## YES — please run option (b). It decides what the fixed kernel buys us.
Fresh boot, mask wireplumber from probing the ImgU (no rebind), confirm imgu0
clean, then stream with freeze-capture armed. The `wait cio gate idle timeout`
during unbind is a real suspect, so distinguishing matters:
- **If CSS boots on a fresh clean imgu0** (rebind was the artifact) → with 9202
  the ImgU may actually **work** (frames, not just a clean stall). Big.
- **If CSS still fails `-EIO` fresh** → the ImgU won't produce frames on this
  hardware; 9202 still crash-proofs it, and CIO2-only + software ISP is the frame
  path. No loss either way.

The fix proceeds regardless of (b)'s result — (b) just tells Bob whether the next
build is "maybe-working ImgU" or "crash-proofing + go CIO2-only for frames."

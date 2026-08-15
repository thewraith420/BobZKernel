# Pixel Slate — Volume Buttons AND Auto-Rotate Are the SAME Kernel Bug

**This supersedes the kernel half of both `VOLUME_BUTTONS_FIX_HANDOFF.md` and
`AUTOROTATE_FIX_HANDOFF.md`.** The volume-button test you ran was the decisive
experiment, and it resolved the question: the sensor FIFO and the buttons are
not two problems. They are one.

## The unified root cause

**The Chrome EC's asynchronous event delivery to the kernel is dead. The EC's
synchronous command interface is fine.**

Everything the EC does *in response to a host command* works — that's why the
accelerometer's `in_accel_*_raw` sysfs reads are live and correct, and why the EC
answered `cros_ec_query_all()` at boot. Everything that depends on the EC
*spontaneously telling the kernel "I have an event"* is broken — buttons,
sensor-FIFO auto-rotate, lid angle, anything MKBP. Same FIFO drain function, same
dead trigger.

Your own evidence, unified:
- EC console shows buttons detected + `MKBP common FIFO depth 16 reached`
  (outgoing queue to the AP overflowing → EC *wants* to deliver, AP isn't
  draining).
- `IRQ 83 (chromeos-ec)` fired **once** the entire boot.
- Sensor FIFO `iio-sensor-proxy` gets `Buffer ... did not have data` — same starved
  FIFO, different queue.

## What the source says (7.1.4, confirmed)

There are **two** independent paths that are each supposed to drain the EC event
FIFO, and on Nocturne **both are silent after boot**:

1. **Hardware IRQ** — `cros_ec.c` requests a threaded IRQ when
   `platform_get_irq_optional()` returns > 0 (it does → IRQ 83):
   ```c
   devm_request_threaded_irq(dev, ec_dev->irq,
           cros_ec_irq_handler, cros_ec_irq_thread,
           IRQF_TRIGGER_LOW | IRQF_ONESHOT, "chromeos-ec", ec_dev);
   ```
   The bottom half loops `cros_ec_get_next_event()` → notifier chain until the
   FIFO is empty. `/proc/interrupts` shows `83-fasteoi` = the kernel configured it
   as **level-low**, exactly as requested — so this is NOT a trigger-type mismatch
   the genirq layer would warn about. A correctly-wired level-low line would
   re-fire on every button. It fires once. So either the EC isn't actually pulling
   *that* line on events, or the line is a vestigial descriptor and the real
   signal goes elsewhere (see path 2).

2. **ACPI Notify** — `cros_ec_lpc.c` also installs a notify handler on `GOOG0004`:
   ```c
   if (value == ACPI_NOTIFY_CROS_EC_MKBP /* 0x80 */ && ec_dev->mkbp_event_supported)
           do { cros_ec_get_next_event(...); notifier_call_chain(...); }
           while (ec_has_more_events);
   ```
   On most x86 cros_ec boards THIS is the real path: the DSDT's EC GPE method
   (`_Qxx`) issues `Notify(EC, 0x80)` when the EC's SCI fires. If Nocturne's DSDT
   doesn't issue that Notify (or issues a different value, or the GPE never fires),
   this path is dead and there's no fallback.

**The single most important line in the whole driver** — `cros_ec.c`, end of
`cros_ec_register()`:
```c
/* Unlock EC that may be waiting for AP to process MKBP events.
   If the AP takes to long to answer, the EC would stop sending events. */
if (ec_dev->mkbp_event_supported)
        cros_ec_irq_thread(0, ec_dev);   /* one manual drain, no IRQ involved */
```
This manual drain runs **once** at registration. It is almost certainly the
source of your "worked for one beat then never again" behaviour, and plausibly the
single counted interrupt is unrelated to it (this call bypasses the IRQ subsystem
entirely). Bottom line: **the command path drains fine on demand; only the async
wakeup that's supposed to *trigger* a drain is missing.**

## DECISIVE EXPERIMENTS (in order — first two need no rebuild)

### 1. Suspend/resume flush — confirms the entire diagnosis, zero tooling
`cros_ec_resume_complete()` deliberately drains the FIFO on resume
(`cros_ec_report_events_during_suspend()` loops `cros_ec_get_next_event`). So:

```
sudo libinput debug-events --device /dev/input/event7   # (leave running in one terminal)
# in the tablet: press Volume Up/Down ~10 times (nothing appears — expected)
systemctl suspend
# wake it back up
```
**If the queued presses all flush to libinput at once on resume**, that *proves*
the FIFO is full of undelivered events and only the async trigger is broken — not
the command path, not the keymap, not evdev. This is the cleanest possible
confirmation and it needs nothing installed.

### 2. Which path (if any) is even trying — `/sys/firmware/acpi/interrupts`
```
grep -H . /sys/firmware/acpi/interrupts/* | grep -v '  0 ' > /tmp/before.txt
# press volume buttons ~20 times
grep -H . /sys/firmware/acpi/interrupts/* | grep -v '  0 ' > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```
plus, in parallel, `grep chromeos-ec /proc/interrupts` before/after.
- A **GPE counter** (`gpeNN`) or `sci` climbing with presses, but no key events →
  the ACPI SCI fires but the DSDT's Notify isn't reaching the driver (wrong Notify
  value / wrong handle). Fixable in the notify path.
- `chromeos-ec` in `/proc/interrupts` climbing → the IRQ *is* firing but the
  threaded drain isn't producing input events (look at the notifier chain /
  `cros_ec_keyb`).
- **Nothing moves anywhere** → the EC's SCI/GPIO signal never reaches the SoC.
  That's a coreboot/DSDT/pinmux-level gap with no async fix → go straight to the
  polling workaround (fix C).

### 3. `dmesg` for genirq / EC complaints
```
dmesg | grep -iE 'cros.?ec|chromeos-ec|irq .*(type|trigger|mismatch)|GOOG000'
```

### 4. DSDT — is there even a Notify for the EC?
```
sudo cp /sys/firmware/acpi/tables/DSDT /tmp/dsdt.aml
iasl -d /tmp/dsdt.aml          # (apt install acpica-tools)
grep -nE 'GOOG0004|Notify|_Qxx|_L[0-9A-F]{2}|_E[0-9A-F]{2}|Interrupt|GpioInt' /tmp/dsdt.dsl
```
Look at `GOOG0004`'s `_CRS` interrupt descriptor (edge vs level, polarity) and
whether any GPE/`_Qxx` method issues `Notify(<EC>, 0x80)`. If there's no
`Notify(...,0x80)` anywhere, path 2 was never going to work on this board and the
IRQ (path 1) is the *only* intended mechanism — which makes path 1's failure the
whole story.

### 5. With the tracing kernel (config change below) — see which handler runs
```
cd /sys/kernel/tracing
echo cros_ec_irq_thread cros_ec_handle_event cros_ec_get_next_event > set_ftrace_filter
echo function > current_tracer ; echo 1 > tracing_on
# press buttons; then:
cat trace
```
If none of these fire on a button press, the wakeup never arrives (paths 1 & 2
both dead). If `cros_ec_get_next_event` fires but returns nothing, the drain runs
but the EC hands back no event — a different, protocol-level bug.

## CANDIDATE FIXES (ranked)

**A. If a GPE is firing but disabled/misrouted (test 2 shows a climbing gpeNN):**
cheapest possible — `echo enable | sudo tee /sys/firmware/acpi/interrupts/gpeNN`
and re-test. If that alone makes events flow, the "fix" is understanding why it
booted disabled.

**B. If test 4 shows an interrupt-descriptor polarity/edge that contradicts
`IRQF_TRIGGER_LOW`:** a board quirk that requests the correct trigger. Note this
lives in the *shared* `cros_ec.c` used by every cros_ec board, so it must be
DMI/quirk-gated to Nocturne, not a blanket change.

**C. Pragmatic guaranteed win — a polling drain (recommended for BobZKernel).**
We *know* `cros_ec_irq_thread(0, ec_dev)` drains successfully on demand (it's what
the boot-time unlock does, and what resume does). So a small periodic poll makes
**both** buttons and auto-rotate work regardless of why the async trigger is dead:

- A `delayed_work` (must be process context — `cros_ec_get_next_event` sleeps on
  an EC command; a timer/softirq won't do) that calls `cros_ec_handle_event()` in
  a loop and re-queues every ~30-50 ms.
- DMI-gate it to `Google_Nocturne` (or make it a module param default-off) so it
  never touches other boards' behaviour.
- Cost: ~20-30 EC polls/sec — negligible for a personal tablet; can back off when
  the screen is off. This is a clean local patch and it's the one I'd write first
  if tests 1-2 confirm "command path fine, async dead," because it fixes the
  entire class of symptom in one place instead of chasing per-consumer plumbing.

**UPDATE — fix C is written:** `patches/cachyos-7.1/9201-cros-ec-poll-event-fifo-fallback.patch`
(applies cleanly to a pristine 7.1.4 tree). It adds a DMI-gated periodic drain of
the EC event FIFO — the same `cros_ec_handle_event()` loop the IRQ thread runs —
from a `delayed_work`, every 40 ms, auto-enabled on `Google`/`Nocturne`, paused
across suspend. It'll be in the next pixel-slate build.

Two things to check on-device once that build is running:
- **DMI match:** confirm `cat /sys/class/dmi/id/sys_vendor` contains `Google` and
  `/sys/class/dmi/id/product_name` contains `Nocturne`. If either differs, the
  auto-enable won't fire — just boot with `cros_ec.ec_event_poll_ms=40` (or
  `echo 40 | sudo tee /sys/module/cros_ec/parameters/ec_event_poll_ms` at runtime,
  though a value set after boot only takes effect on the next EC (re)register, so
  the cmdline is the reliable way).
- **Confirmation it's live:** `dmesg | grep -i "polling FIFO"` should show
  `EC event IRQ/notify unreliable on this board; polling FIFO every 40 ms`. Then
  volume buttons and auto-rotate-orientation should both work with no other change.
- **Tuning:** 40 ms ≈ 25 Hz. If buttons feel laggy, lower it (e.g. 20); if you
  want less wakeup churn, raise it. `0` disables (e.g. if the async path ever gets
  root-fixed). No rebuild needed for any of this.

The suspend/resume flush test (test 1) is no longer required to justify the patch —
it's written — but it's still a nice independent confirmation of the root cause if
you get the self-wake sorted (try `rtcwake -m mem -s 15` for a bounded sleep).

## Config change already made (BobZKernel side)

To make tests 3 & 5 possible at all, I enabled tracing/dyndbg in
`configs/config-7.1-pixel-slate` (they were both off, which is why this has been
so hard to see):
```
CONFIG_DYNAMIC_DEBUG=y
CONFIG_DYNAMIC_DEBUG_CORE=y
CONFIG_FTRACE=y
CONFIG_FUNCTION_TRACER=y
```
Rebuild with `./scripts/update-and-build-7.1.sh` on the `pixel-slate` branch.
(LTO_CLANG_FULL caveat: if function tracing breaks the build, drop
`CONFIG_FUNCTION_TRACER`, keep dyndbg — test 5 loses ftrace but everything else
stands.)

## What is NOT part of this bug

The **mutter / auto-rotate-application** problem (screen doesn't rotate even when
`AccelerometerOrientation` D-Bus *is* updating) is a **separate, userspace** issue
— see the mutter round-2 notes. Note the interaction though: today the sensor
FIFO is starved, so with poll-driver forcing (`iio-poll-accel`) userspace still
gets orientation by *reading raw values*, bypassing the dead FIFO. If fix C lands
and the FIFO starts delivering, you could drop the poll-driver udev override and
use the intended buffered path — but that's optional and independent of getting
rotation to actually apply.

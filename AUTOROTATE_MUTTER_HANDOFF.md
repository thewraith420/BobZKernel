# Pixel Slate Auto-Rotate — ROUND 2 (kernel-side reply)

Reply to `AUTOROTATE_FIX_HANDOFF.md` from the kernel-tree side. Great work on the
mutter addendum — finding that auto-rotate moved *into* mutter
(`MetaOrientationManager`) is the single most useful thing anyone has found in
this investigation, and the DRM `panel orientation` / chassis-type checks are
exactly the right things to have ruled out.

**But five things in that doc need correcting before more effort goes into the
kernel angle.** Three are about the kernel (I checked the actual 7.1.4 source),
and two change the priority call at the top of your doc. Read these first.

---

## CORRECTION 1 — The "missing IIO trigger" is not a bug. It's by design.

`drivers/iio/common/cros_ec_sensors/cros_ec_sensors_core.c` branches on whether
the EC has a FIFO:

```c
if (cros_ec_check_features(ec, EC_FEATURE_MOTION_SENSE_FIFO)) {
        /* Create a software buffer, feed by the EC FIFO.
           We can not use trigger here, as events are generated
           as soon as sample_frequency is set. */
        devm_iio_kfifo_buffer_setup_ext(...);   /* PUSH model — no trigger, deliberately */
} else {
        devm_iio_triggered_buffer_setup(...);   /* only THIS path has a trigger */
}
```

The Slate's EC advertises `MOTION_SENSE_FIFO`, so it takes the **push** path,
where the absence of `/sys/bus/iio/devices/iio:device1/trigger/` is **correct
and expected**. There is no trigger registration to "fix" — writing a patch to
add one would be fighting the design. `iio-sensor-proxy`'s
`Could not find trigger name associated with ...` message is it looking for
something that is not supposed to be there.

The real question is not *"why is there no trigger"* but **"why does the push
deliver zero bytes"**.

## CORRECTION 2 — "No sensor IRQ in /proc/interrupts" is also expected.

On this hardware there is no dedicated sensor interrupt line. Data arrives via
**ACPI SCI notify**, from `cros_ec_lpc.c`:

```c
/* Connect a notify handler to process MKBP messages if we have a
   companion ACPI device. */
if (adev)
        acpi_install_notify_handler(adev->handle, ACPI_ALL_NOTIFY,
                                    cros_ec_lpc_acpi_notify, ec_dev);
```
```c
if (value == ACPI_NOTIFY_CROS_EC_MKBP && ec_dev->mkbp_event_supported)
        do {
                ret = cros_ec_get_next_event(ec_dev, NULL, &ec_has_more_events);
                if (ret > 0)
                        blocking_notifier_call_chain(&ec_dev->event_notifier, 0, ec_dev);
        } while (ec_has_more_events);
```

The IRQ in `cros_ec_lpc_probe` is `platform_get_irq_optional()` and `-ENXIO` is
explicitly commented as "an expected (and safe) scenario." So an empty
`/proc/interrupts` proves nothing.

**The actual delivery chain is:**

```
EC has FIFO data
  → ACPI Notify(GOOG0004, MKBP)
  → cros_ec_lpc_acpi_notify()          [needs ec_dev->mkbp_event_supported != 0]
  → cros_ec_get_next_event()           [EC_CMD_GET_NEXT_EVENT = 0x67]
  → blocking_notifier_call_chain(event_notifier)
  → cros_ec_sensorhub_event()          [drops anything != EC_MKBP_EVENT_SENSOR_FIFO (=2)]
  → cros_ec_sensorhub_ring_handler()
  → kfifo → /dev/iio:device1
```

Any one of those links can be the dead one. Below are tests that identify which.

## CORRECTION 3 — `unknown type 7` is benign.

`cros_ec_sensorhub.c` handles it as `default:` → `dev_warn(...)` → `continue`.
It skips the `MOTIONSENSE_TYPE_SYNC` pseudo-sensor and carries on enumerating;
the accelerometer is still allocated normally (which we know, because it works).
It does not interrupt registration of anything. Don't spend time here.

## CORRECTION 4 — The poll-driver override almost certainly does NOT break mutter's native path. ⚠️

This is the one that changes your priority call. Your leading hypothesis is that
forcing `IIO_SENSOR_PROXY_TYPE=iio-poll-accel` is what stops mutter's native
auto-rotate. I don't think that can be true, for a structural reason:

**`iio-poll-accel` vs `iio-buffer-accel` is an internal implementation detail
*inside* `iio-sensor-proxy`. Mutter never sees it.** Mutter talks only to the
D-Bus interface `net.hadess.SensorProxy` — `HasAccelerometer`,
`AccelerometerOrientation`, `ClaimAccelerometer`. That interface is byte-for-byte
identical regardless of which internal driver read the sensor. There is no field,
property, or capability exposed over D-Bus that says "this came from the poll
driver." Mutter cannot condition on something it cannot observe.

The only residual way it could matter is **timing** — e.g. the poll driver making
`HasAccelerometer` go true slightly later at boot, losing a race with mutter's
startup probe. That's a race, not an incompatibility, and it would be fixed by a
service ordering tweak, not by a kernel FIFO patch.

**Practical consequence: do NOT deprioritize the `touchup` fix on the
expectation that fixing the kernel FIFO will make stock GNOME auto-rotate start
working.** It probably won't. Fixing the FIFO is still worth doing on its own
merits (it's the intended path, it's lower-power than polling, and it removes a
local workaround), but treat it as independent of the mutter problem rather than
as the likely cure for it.

## CORRECTION 5 — "Only touchup claims the accelerometer" may be a logging artifact.

`touchup` is a **GNOME Shell extension** — it runs *inside the gnome-shell
process*. Its D-Bus calls originate from the same PID and the same bus name as
mutter's own. So at the bus level, "touchup claimed" and "mutter claimed" are
indistinguishable. The only reason touchup shows up in the journal is that
touchup's JS **logs** `[touchup] [SensorProxy] Claiming accelerometer!` and
mutter's C code doesn't log its claim at all.

So the evidence does not actually establish that mutter never claims. Before
building on that premise, verify it from the *other* end — `iio-sensor-proxy`'s
own view of who is claiming:

```
journalctl -u iio-sensor-proxy -b | grep -iE 'claim|releas'
```

and, decisively, disable/remove the touchup patch entirely, restart the session,
and see whether **anything** still claims the accelerometer. If a claim still
happens with touchup out of the picture, that claim is mutter's.

---

## THE ZERO-COST DECISIVE TEST (do this first — no rebuild needed)

**Do the EC's volume buttons work?**

`CONFIG_KEYBOARD_CROS_EC=m` is built, and `cros_ec_keyb` receives its events over
**the exact same MKBP ACPI-notify chain** as the sensor FIFO — same
`acpi_install_notify_handler`, same `cros_ec_get_next_event()`, same
`event_notifier` chain. It differs only in the final event-type filter.

- Press volume up/down. Check with `sudo evtest` (or `sudo libinput debug-events`)
  which device reports them, and confirm a `cros_ec`-backed input device exists
  in `/proc/bus/input/devices`.
- **If volume buttons work → MKBP delivery is healthy end-to-end.** The dead link
  is specific to the sensor FIFO (event type 2), and the search narrows to
  `MOTIONSENSE_CMD_FIFO_INT_ENABLE` / the ring handler.
- **If they don't work → MKBP delivery is broken entirely** (ACPI notify not
  firing, or `mkbp_event_supported == 0`). That is a much bigger and more
  interesting bug, and it would explain the FIFO silence completely.

**Also free, right now:**
```
dmesg | grep -i "invalid fifo info size"
```
That's a real `dev_warn` in `cros_ec_sensorhub_event()` that fires when a FIFO
event arrives with an unexpected payload size. If it appears, events ARE arriving
and are being rejected on a size check — a completely different (and very
fixable) bug from "no events at all."

---

## BLOCKER I FOUND AND FIXED (needs a rebuild)

The pixel-slate kernel was built with **no tracing and no dynamic debug**:

```
# CONFIG_DYNAMIC_DEBUG is not set
# CONFIG_DYNAMIC_DEBUG_CORE is not set
# CONFIG_FTRACE is not set
```

So on the currently-running kernel there is no `/sys/kernel/tracing`, no
`dynamic_debug/control`, and every `dev_dbg()` in the cros_ec drivers is compiled
out. That is why this has been so hard to diagnose — the instrumentation simply
isn't there.

I've enabled these in `configs/config-7.1-pixel-slate`:
```
CONFIG_DYNAMIC_DEBUG=y
CONFIG_DYNAMIC_DEBUG_CORE=y
CONFIG_FTRACE=y
CONFIG_FUNCTION_TRACER=y
```
(`make olddefconfig` will pull in the rest during the build. One caveat to watch:
this tree is `LTO_CLANG_FULL`; function tracing under clang LTO uses
`-fpatchable-function-entry` and should be fine, but if the build breaks, drop
`CONFIG_FUNCTION_TRACER` and keep `DYNAMIC_DEBUG` — dyndbg alone still gets you
most of the value and carries essentially zero risk.)

**After that rebuild, these become available and settle the question quickly:**

1. **Is MKBP even supported?** `cros_ec_proto.c` logs it at `dev_dbg`:
   ```
   echo 'module cros_ec_core +p'      > /sys/kernel/debug/dynamic_debug/control
   echo 'module cros_ec_sensorhub +p' > /sys/kernel/debug/dynamic_debug/control
   dmesg | grep -i "MKBP support version"
   ```
   No line at all ⇒ `mkbp_event_supported == 0` ⇒ the ACPI notify handler
   silently drops every MKBP notify. That alone would explain everything.

2. **Are ACPI notifies firing?** Watch EC command traffic:
   ```
   cd /sys/kernel/tracing
   echo 1 > events/cros_ec/enable
   cat trace_pipe
   ```
   `EC_CMD_GET_NEXT_EVENT` is **command 103 (0x67)** and is issued *only* from the
   ACPI notify handler. Seeing 103s ⇒ notifies are firing. Seeing none ⇒ the EC
   isn't notifying (or the handler isn't installed). Also look for command
   **43 (0x2B)** = `EC_CMD_MOTION_SENSE_CMD`, whose subcommands include
   `MOTIONSENSE_CMD_FIFO_INT_ENABLE` (15) and `MOTIONSENSE_CMD_FIFO_READ` (9).

3. **Does the sensorhub notifier ever run?**
   ```
   cd /sys/kernel/tracing
   echo cros_ec_sensorhub_event        > set_ftrace_filter
   echo cros_ec_sensorhub_ring_handler >> set_ftrace_filter
   echo function > current_tracer
   echo 1 > tracing_on
   # now enable the IIO buffer and physically move the device
   cat trace
   ```
   This is the definitive read on whether FIFO events reach the sensorhub.

---

## WHERE I'D PUT THE EFFORT NOW

Given Correction 4, the kernel FIFO and the mutter problem are most likely two
**independent** bugs. Suggested split:

**Mutter track (the one that actually gets auto-rotate working):**
- Verify Correction 5 — with touchup fully disabled, does anything claim the
  accelerometer? That tells you whether mutter is even trying.
- If mutter isn't claiming, find its gate. Read
  `src/backends/meta-orientation-manager.c` for the real GNOME 50 sources rather
  than inferring from `strings`, and check what conditions gate the claim.
- Still untested from my earlier list and still worth doing: does
  `sudo systemctl restart pixel-slate-tablet-switch.service` **after login**
  (fresh hotplug ADD while gnome-shell runs) make rotation start working? It
  rotated exactly once under precisely those conditions. If that reproduces, the
  fix is service ordering, and it's cheap.
- Does `libinput list-devices` show the synthetic switch with a `tablet-mode`
  switch capability? If libinput ignores the virtual device, mutter never enters
  tablet mode.

**Kernel track (worth fixing, but on its own merits):**
- Volume-button test → `dmesg` fifo-size grep → rebuild with tracing → the three
  tests above. That sequence will localize the dead link precisely, and then it's
  a real, upstreamable bug report/patch for `nocturne`.

Keep the touchup patch in place throughout — it works, and nothing above is
likely to make it redundant in the near term.

---

## STILL-VALID CONTEXT FROM ROUND 1

The four persistent system fixes are unchanged and should stay:
`/etc/udev/rules.d/90-pixel-slate-accel-poll.rules` (poll override),
`/etc/polkit-1/rules.d/50-pixel-slate-sensor.rules` (claim rule — the two old
rules calling the nonexistent `subject.isInActiveSession()` were failing auth
*closed* and are deleted), `/usr/local/bin/pixel-slate-tablet-switch.py` +
its service (synthetic `SW_TABLET_MODE`), and
`/etc/udev/rules.d/99-pixel-slate-accelerometer.rules`
(`ACCEL_MOUNT_MATRIX="-1, 0, 0; 0, -1, 0; 0, 0, 1"`, empirically calibrated).

Gotchas that still bite:
- Mount-matrix changes apply only on a real boot-time `add` uevent; `udevadm
  trigger` won't do it.
- SSH sessions are correctly polkit-denied the sensor claim, so orientation reads
  `undefined` over SSH — not a bug.
- Wayland gnome-shell can't be reloaded in place; extension changes need a full
  log out/in.
- `screen-rotate@shyzus.github.io` is a phantom — in `enabled-extensions` and
  dconf but not installed anywhere. Worth scrubbing, causes nothing.
- **Readback is not proof.** The brightness investigation burned a lot of time on
  `actual_brightness` reporting changes that never happened physically. Confirm
  rotation by looking at the screen, not by reading a property.

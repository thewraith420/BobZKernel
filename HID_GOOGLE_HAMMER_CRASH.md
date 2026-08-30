# Bug report: hid_google_hammer crashes the kernel on boot

**Date:** 2026-08-28
**From:** slate. **To:** build machine.
**Not an ask for a build** - this is a bug report plus one small documentation
request, since the fix (a cmdline blacklist) already works and is in place.

## Summary

`hid_google_hammer` is blacklisted on this machine
(`module_blacklist=hid_google_hammer,cros_usbpd_notify` in
`/etc/default/grub`). That blacklist has been in place since early in this
kernel's life, originally because loading the module made boot take a very
long time. Tonight we tested *why*, with a one-shot GRUB edit (removed just
for that boot, never written to disk) to load it and watch.

**It is not a slow probe. It is a kernel crash** - a general protection fault
during module load, which taints the kernel `DIE` and throws a second fault
immediately after. The "long boot" is the deferred-probe retry timer
eventually giving up on a device left in a bad state by the crash, roughly
10 seconds later - not an infinite hang, just recovery from already having
crashed once.

## The oops (transcribed from a phone photo of the console; exact hex digits
may have a transcription error or two, the structure and text are accurate)

```
[   0.814891] Oops: general protection fault, probably for non-canonical address 0x415b10c48348d801: 0000 [#1]
[   0.814920] CPU: 1 UID: 0 PID: 136 Comm: udev-worker Tainted: G    D    7.1.11-BobZKernel-pixel-slate
[   0.814940] Tainted: [D]=DIE
[   0.814948] Hardware name: Google Nocturne/Nocturne, BIOS MrChromebox-2512.1 01/15/2026
[   0.814961] RIP: 0010:__se_sys_finit_module+0x274/0x560
[   0.815016] RCX: 415b10c48348d801
...
[   0.815131] Call Trace:
[   0.815151]  ? __x64_sys_close+0xdd/0x180
[   0.815204]  x64_sys_call+0x2ab1/0x2e60
[   0.815225]  do_syscall_64+0x136/0x900
[   0.815323]  entry_SYSCALL_64_after_hwframe+0x76/0x7e
[   0.820173] Modules linked in: sdhci cros_ec_keyb hid_google_hammer(+) i2c_hid_acpi
              hid_vivaldi_common idma64 hid_logitech_dj(+) hid_generic usbhid hid
[   0.821110] ---[ end trace 0000000000000000 ]---
[   0.821554] RIP: 0010:mutex_lock+0x18/0x40          <- second fault, immediately after
[   0.827438] note: udev-worker[136] exited with preempt_count 1
[  10.804406] platform GOOG0007:00: deferred probe pending: (reason unknown)
```

Key facts, all clearly legible in the photo:

- **`__se_sys_finit_module`** - the crash is inside module loading itself,
  triggered by `udev-worker` calling `finit_module()` on `hid_google_hammer.ko`
  as it auto-binds. Not the module simply misbehaving after loading - the
  *load* itself faults.
- **`RCX: 415b10c48348d801`** - the address the fault is "probably for" is
  visibly garbage, not a plausible kernel or user pointer. This reads as the
  driver dereferencing a pointer built from data it expected to find and
  didn't - most likely an ACPI package under `GOOG000B` or `GOOG0004`
  (the alias table for this driver includes `acpi*:GOOG000B:*`, and that
  device is present in this board's ACPI namespace, nested under the EC
  device `GOOG0004`, even with no physical keyboard base attached).
- **`Tainted: [D]=DIE`** - the kernel's own label for "this already crashed
  once," not a benign warning taint.
- **A second RIP at `mutex_lock`** immediately follows the first fault -
  consistent with the first crash leaving something (a lock, a list) in a
  corrupted state rather than failing cleanly.
- **The ~10s gap to `GOOG0007:00: deferred probe pending`** is very likely the
  visible cost of that corruption: some other Google platform device's probe
  sits in the deferred-probe retry queue, presumably because whatever
  `hid_google_hammer` was supposed to provide never arrived. This is what
  reads as "eventually gets past it, but it takes forever" - the retry timer
  giving up, not a true hang.

## Update, same evening: exact root cause found, and it's a real kernel bug

The section right below this one was the original guess, written before
actually reading MrChromebox's coreboot source or the kernel driver source.
Both have now been read. The guess was half right (firmware-related) but
wrong on the mechanism - **this is not missing/malformed ACPI data.** It's a
missing NULL check in the Linux driver, and it has a one-line fix.

**Coreboot side:** MrChromebox's `CBAS`/`GOOG000B` ACPI device
(`src/ec/google/chromeec/acpi/cros_ec.asl`, generic upstream coreboot code,
not board-specific) is a bare 3-line stub - `_HID`, `_UID`, `_DDN` only, no
`_STA`, `_CRS`, or `_DSD`. That's not really a coreboot bug; a device with no
`_STA` simply defaults to "present" per the ACPI spec. Stock ChromeOS's own
payload (depthcharge) apparently completes whatever wiring this device needs
at runtime, in a way EDK2/UEFI (MrChromebox's payload choice here) doesn't
replicate.

**Kernel side, the actual crash mechanism:** `hid-google-hammer.c`'s
`__cbas_ec_probe()` does this, with no check in between:

```c
struct cros_ec_device *ec = dev_get_drvdata(pdev->dev.parent);
...
error = cbas_ec_query_base(ec, false, &base_supported);   // ec deref'd immediately
```

`cbas_ec_query_base()` dereferences `ec` right away to build and send an EC
host command (`cros_ec_cmd_xfer_status()`). The driver does **not** read any
ACPI property directly - it gets its `cros_ec_device` handle purely by
reaching into its own parent platform device's drvdata. On this board that
comes back NULL or garbage (consistent with `RCX: 415b10c48348d801` in the
oops - not a plausible pointer), and the very next line dereferences it. No
ACPI data is walked or misparsed; the crash is a straightforward missing-
NULL-check bug that any board with the same drvdata gap would also hit.

This also accounts for **both** faults in the trace, not just the first:
`cbas_ec_probe()` takes `cbas_ec_reglock` *before* calling
`__cbas_ec_probe()`, so the crash happens with that mutex still held -
matching the second RIP (`mutex_lock+0x18/0x40`) immediately after.

**The fix is one missing null check**, patch attached at
`~/hid-google-hammer-null-check.patch`:

```c
struct cros_ec_device *ec = dev_get_drvdata(pdev->dev.parent);
if (!ec)
	return -ENODEV;
```

This is a legitimate upstream kernel robustness bug, not a coreboot-specific
workaround - worth reporting to the hid-google-hammer maintainers regardless
of this board. It's also something you could carry as a local BobZKernel
patch: with the check in place, `hid_google_hammer` would fail its probe
cleanly (`-ENODEV`) instead of crashing, which means **the `module_blacklist`
entry could be dropped entirely** - same practical outcome (no working base
detection) with zero crash risk, and no special cmdline knowledge required
on a fresh install. Whether real Whiskers base detection could ever work on
this coreboot build is a separate, harder question (needs whatever actually
populates that parent drvdata link on stock ChromeOS/depthcharge - not yet
tracked down) - but this patch is worth carrying either way.

Not yet done: testing the patched module on real hardware (the one-shot GRUB
test above was against the *unpatched* module) - do that before actually
dropping the blacklist, in case there's a deferred-probe race worth watching
play out first.

## Original (superseded) guess - kept for the record

`hid_google_hammer` covers a family of Google detachable-keyboard controllers
(Pixelbook's Hammer, Pixel Slate's Whiskers, others - all via the same
`GOOG000B` ACPI ID). On stock ChromeOS firmware the ACPI tables under that
device are populated with whatever the driver expects. This machine runs
**MrChromebox-2512.1**, third-party coreboot, and it looks like the relevant
ACPI data for `GOOG000B`/`GOOG0004` is missing or shaped differently there -
the driver has no defensive check for that, and dereferences garbage instead
of failing gracefully.

*(Superseded above: the driver never reads ACPI data for this device at
all - the real mechanism is the parent-device drvdata dereference.)*

## What's already handled, and what's being asked for

**Already fine:** the blacklist works, is in place, and this machine boots in
~17 seconds every time. No urgency, nothing broken today.

**The actual ask:** this knowledge currently lives in exactly one place -
`/etc/default/grub` on this one Ubuntu install. It is not recorded in
BobZKernel or chromebook-fixer anywhere. If this machine is ever reinstalled,
or a fresh kernel image is ever installed without carrying that cmdline
forward, this crash will recur on first boot with no warning and no obvious
cause - a much worse debugging experience than a bug report can convey, since
by then there'd be no memory of ever having chased it down.

Could `module_blacklist=hid_google_hammer` be added to the required-cmdline
notes on BobZKernel's `pixel-slate` branch, alongside the existing
`i915.enable_dpcd_backlight=2 i915.enable_psr=0` documentation? Same
treatment, same reason: a parameter this board needs that nothing will
remind a future install about otherwise.

**Optional, if it's ever interesting:** see the root-cause update above - the
one-line patch at `~/hid-google-hammer-null-check.patch` turns the crash into
a clean probe failure and is worth reporting upstream regardless of this
board. Carrying it locally would let the `module_blacklist` entry go away
entirely, once it's actually been tested on hardware. Not urgent either way;
the blacklist is a complete, working answer on its own.

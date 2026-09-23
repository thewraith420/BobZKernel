# nightfall-kernel

The kernel for [Nightfall Boot Manager](https://github.com/thewraith420/nightfall-boot-manager),
built to boot on **most x86-64 PCs**, not only the Google Pixel Slate.

| Branch | Kernel | Target | Config |
|---|---|---|---|
| `picker-kernel` | 7.1 (EOL, frozen) | Pixel Slate only | `config-7.1-picker` |
| **`nightfall-kernel`** | **7.2** | any PC, including the Slate | `config-7.2-nightfall` |

`picker-kernel` is the Slate's proven kernel and is left alone (release `v7.1.13-picker`
was built from it). `nightfall-kernel` started as a copy of it and only ever adds.

Build with `./scripts/update-and-build-7.2.sh` on this branch. The 7.1 scripts refuse to
run here on purpose.

## Requirement: Secure Boot must be off

This kernel is unsigned, so with Secure Boot enabled the firmware/bootloader refuses to
load it and Nightfall never starts. Signing is out of scope, so **on any machine other than
the Slate, Secure Boot has to be disabled** in the firmware setup. (The Slate runs coreboot
and has no Secure Boot, which is why it never came up there.)

Note what Secure Boot does *not* do here: mainline 7.2 does not turn on kernel lockdown
because of Secure Boot (the EFI code only logs "Secure boot enabled"; automatic lockdown is
a distro patch this kernel does not carry), and `CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y`. So
once Nightfall is running, `kexec_load` is not blocked by lockdown unless someone passes
`lockdown=` on the command line. Nightfall's kexec preflight reads
`/sys/kernel/security/lockdown` (needs `SECURITYFS` + the lockdown LSM, both built in) and
only fires in that case. `KEXEC_FILE` and `KEXEC_SIG` stay built in so a later move to
`kexec_file_load` needs no kernel change.

## What was added over the Slate kernel

Everything is `=y`, never `=m`: Nightfall's initramfs has no `modprobe` and no
`/lib/modules`, so a module is invisible to it.

- **Storage:** NVMe, SATA/AHCI (+ legacy PIIX), Intel VMD (NVMe hidden behind a "RAID mode"
  BIOS setting), on top of the Slate's eMMC and USB mass storage.
- **Filesystems:** btrfs, xfs, f2fs (Slate already had ext4, vfat/exFAT/NTFS3, ISO9660/UDF).
- **Input:** USB HID and the PS/2 mouse.
- **Touchpads:** Intel GPIO/pinctrl drivers for every recent PCH generation. i2c-hid
  touchpads need these for their interrupt line (same class of bug as the Slate's
  missing LPSS/SUNRISEPOINT).
- **Graphics:** unchanged. simpledrm on the EFI framebuffer is the universal fallback, so
  no native amdgpu/nouveau (they need firmware blobs the initramfs does not have).
  Bochs and virtio-gpu are built in so a build can be smoke-tested in QEMU.
- **Codegen:** `-march=x86-64-v2 -mtune=generic` instead of `-march=skylake`, which can
  fault on older CPUs. Same baseline as `generic-build`.

## Patches: audited for other hardware

The Slate patch stack is carried, but each patch was checked for whether it can touch a
machine that is not a Slate.

| Patch | Gate | Verdict |
|---|---|---|
| 9201 cros-ec poll, 9203 imx sensors, 9207 GOOG0007, 9208 i915 PSR | DMI `Google` / `Nocturne` | inert elsewhere |
| 9204 IOMMU ImgU identity domain | PCI `8086:1919` | inert elsewhere |
| 9202 ipu3, 9205 v4l2loopback, 9206 hammer null-check | code not built here / plain null guard | inert |
| **9200 i915 AUX backlight** | **none in the pixel-slate version** | **replaced** |

The `pixel-slate` version of 9200 relaxes the eDP backlight check for *every* panel, and its
own header says "Do NOT apply on the other variants". On a generic kernel that could switch
a panel that needs PWM onto the AUX path and leave it dark. This branch carries
`9200-i915-nocturne-aux-backlight-dmi.patch` instead: identical behaviour on the Slate,
upstream's logic everywhere else.

## Guard: never lose Slate work

`./scripts/check-nightfall-superset.sh` fails if any symbol that is `=y` in the frozen
`picker-kernel` config is no longer `=y` here. Across kernel versions it sorts each missing
symbol into "removed upstream", "migrated (transitional stub)", or **real loss**; only the
last one fails. Run it after every config change and every kernel bump.

## Verification status

- **QEMU smoke test** (`scripts/qemu-smoke-nightfall.sh`, BIOS and UEFI): 42 of 42 checks pass.
  NVMe, AHCI and virtio disks, USB and PS/2 keyboards and mice, a DRM device, DMI board name,
  the lockdown file, and all nine filesystems are visible to a module-less initramfs.
- **Real hardware, one machine:** Lenovo 82XV (board LNVNB161216), 13th-gen Core i5-13420H
  (Alder Lake-P), booted from a USB stick through a GRUB entry. It found its root, drew the
  menu, took input from both the built-in AT keyboard and the laptop's ITE hotkey/EC keyboard,
  and kexec'd into the installed Linux Mint kernel.
- **Pixel Slate:** reported working by its owner, including the touchscreen, with none of the
  old i915 workaround options passed (see the options section below). A hands-on report, not a
  scripted test.
- **Not tested:** any AMD machine, other Intel generations, NVMe/AHCI as the root disk on real
  hardware, non-UEFI (BIOS) boot on real hardware, and Fedora/openSUSE (BLS) discovery on real
  hardware. The frozen `picker-kernel` / `v7.1.13-picker` stays available as the Slate-only fallback.

**Verify which kernel is actually installed.** A wrong image once sat on the test stick for a
whole day and every symptom was blamed on the kernel. Compare the installed file with the
`SHA256SUMS` published beside the release: `sha256sum /boot/nightfall/vmlinuz`.

## Command-line options: do not copy the Slate's to other machines

The Slate's old picker kernel needed two i915 options to light its panel. Copying them onto
other hardware is harmful (on a Lenovo Alder Lake-P it was suspected of breaking the display
before that turned out to be a wrong-kernel mix-up), so do not carry them forward blindly:

- `i915.enable_psr=0`: patch 9208 in this kernel applies the same thing automatically, keyed
  on the Nocturne DMI match. The frozen `picker-kernel` never had 9208, which is why it needed
  the option. Nothing to pass on the Slate, and nothing to pass elsewhere.
- `i915.enable_dpcd_backlight=2`: needed by the frozen 7.1 `picker-kernel` on the Slate. It has
  been confirmed not needed with this kernel by the Slate's owner, but **why is not yet
  explained**. In this kernel's i915, AUTO mode only tries the VESA backlight path if the
  panel's VBT says so or the panel reports eDP 1.5+ (see `intel_dp_aux_backlight.c`), and
  nothing here changes that for the Slate. The likely cause is a firmware/VBT change, not the
  kernel. Keep the option handy for the Slate, and do not add it to anything else.

## Known limits

- Secure Boot must be off (see above).
- No GuC/DMC firmware is built in, so on recent Intel GPUs the render engine reports "wedged".
  That does not affect display: Nightfall only uses dumb-buffer scanout, never the render engine.
- Root and `/boot` discovery, the keyboard/mouse UI, resolution scaling and the hidden backup
  menu are handled by Nightfall itself, not this kernel. Use a Nightfall build that includes them.
- Encrypted (LUKS/LVM) roots are not a kernel problem, because Nightfall never opens the root
  and the distro's own initrd does, but discovery still has to be able to read `/boot`.
- The portable installer for this branch deliberately omits the `linux-headers` tarball
  (~700 MB): Nightfall's initramfs never loads a module, so nothing could use it.

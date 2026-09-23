#!/bin/bash
# QEMU smoke test for the nightfall-kernel bzImage: does the kernel actually SEE the
# hardware a generic PC has? Boots it with a tiny initramfs (no modules, exactly like
# Nightfall's real one) and asserts that the built-in drivers enumerate their devices.
#
# This proves the kernel side only. It does not run Nightfall's UI.
#
# Usage: ./scripts/qemu-smoke-nightfall.sh [bzImage] [bios|uefi|both]
set -uo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${1:-$BASE_DIR/builds/linux-7.2/arch/x86/boot/bzImage}"
MODES="${2:-both}"
WORK="$(mktemp -d /tmp/nf-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$KERNEL" ] || { echo "no kernel at $KERNEL" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo "qemu-system-x86_64 not installed" >&2; exit 2; }

# ---- initramfs: busybox + the libs it needs (no modprobe, no /lib/modules) ----------
R="$WORK/root"; mkdir -p "$R"/{bin,proc,sys,dev,lib,lib64}
cp "$(command -v busybox)" "$R/bin/busybox"
ldd "$R/bin/busybox" | awk '/=>/ {print $3} /^\t\// {print $1}' | sort -u | while read -r lib; do
    mkdir -p "$R$(dirname "$lib")"; cp -L "$lib" "$R$lib"
done
cat > "$R/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev
mount -t securityfs securityfs /sys/kernel/security 2>/dev/null
# USB enumeration is asynchronous: give the xHCI devices time to bind their HID drivers
# (Nightfall itself rescans input devices every second, so this only matters for the test)
i=0; while [ $i -lt 16 ]; do grep -q 'USB Tablet' /proc/bus/input/devices && break; sleep 0.5; i=$((i+1)); done
sleep 1
echo "FACT kernel=$(uname -r)"
for f in $(cut -f2 /proc/filesystems | sort -u); do echo "FACT fs=$f"; done
for b in $(ls /sys/block); do echo "FACT block=$b"; done
grep '^N: Name=' /proc/bus/input/devices | sed 's/^N: Name="\(.*\)"$/FACT input=\1/'
for d in $(ls /dev/dri 2>/dev/null); do echo "FACT dri=$d"; done
for l in $(ls /sys/class/drm 2>/dev/null | grep -E '^card[0-9]+$'); do
    echo "FACT drm_driver=$l:$(basename "$(readlink /sys/class/drm/$l/device/driver)" 2>/dev/null)"
done
echo "FACT dmi_board=$(cat /sys/class/dmi/id/board_name 2>/dev/null)"
echo "FACT lockdown=$(cat /sys/kernel/security/lockdown 2>/dev/null)"
dmesg | grep -iE 'hid|usb 1-|xhci' | head -25 | sed 's/^/FACT dmesg=/'
echo "FACT done=1"
poweroff -f
INIT
chmod +x "$R/init"
( cd "$R" && find . | cpio -o -H newc --quiet | gzip -1 ) > "$WORK/initrd.gz"

# ---- virtual disks ---------------------------------------------------------------------
for d in nvme sata virt; do truncate -s 64M "$WORK/$d.img"; done
ACCEL="-machine q35"; [ -w /dev/kvm ] && ACCEL="-machine q35,accel=kvm -cpu host" || ACCEL="-machine q35 -cpu qemu64"
DEVS=(
  -drive "if=none,id=n0,file=$WORK/nvme.img,format=raw" -device nvme,drive=n0,serial=nfsmoke
  -device ich9-ahci,id=ahci -drive "if=none,id=s0,file=$WORK/sata.img,format=raw" -device ide-hd,drive=s0,bus=ahci.0
  -drive "if=none,id=v0,file=$WORK/virt.img,format=raw" -device virtio-blk-pci,drive=v0
  -device qemu-xhci -device usb-kbd -device usb-tablet
  -smbios type=2,manufacturer=NFTest,product=NFBoard -vga std -display none -serial "file:$WORK/serial.log" -no-reboot -m 1024
)

check() {  # check <label> <fact-regex>
    if grep -Eq "^FACT $2\$" "$WORK/serial.log"; then printf '  PASS  %s\n' "$1"; else printf '  FAIL  %s   (wanted: %s)\n' "$1" "$2"; FAILS=$((FAILS+1)); fi
}

run_mode() {
    local mode="$1" fw=()
    : > "$WORK/serial.log"
    if [ "$mode" = uefi ]; then
        local code=/usr/share/OVMF/OVMF_CODE_4M.fd vars=/usr/share/OVMF/OVMF_VARS_4M.fd
        [ -f "$code" ] || { echo "  SKIP  uefi (no OVMF)"; return; }
        cp "$vars" "$WORK/vars.fd"
        fw=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$WORK/vars.fd")
    fi
    echo "== $mode boot =="
    timeout 240 qemu-system-x86_64 $ACCEL "${fw[@]}" -kernel "$KERNEL" -initrd "$WORK/initrd.gz" \
        -append "console=ttyS0 panic=-1" "${DEVS[@]}" >/dev/null 2>&1
    sed -i 's/\r$//' "$WORK/serial.log"    # the serial console emits CRLF; it would defeat every end-anchored match
    if ! grep -q "^FACT done=1" "$WORK/serial.log"; then
        echo "  FAIL  kernel did not reach init (tail of console follows)"; tail -15 "$WORK/serial.log" | sed 's/^/        /'
        FAILS=$((FAILS+1)); return
    fi
    grep -E '^FACT (kernel|drm_driver)=' "$WORK/serial.log" | sed 's/^FACT /  info  /'
    # harness self-checks: true on ANY kernel, so a FAIL here means the harness is broken, not the kernel
    check "harness: proc/sysfs/devtmpfs registered" 'fs=(proc|sysfs|devtmpfs)'
    check "image under test is a *-nightfall build (not a stale bzImage)" 'kernel=.*-nightfall'
    check "NVMe disk (BLK_DEV_NVME)"        'block=nvme0n1'
    check "SATA disk via AHCI (SATA_AHCI)"  'block=sd[a-z]'
    check "virtio-blk disk"                 'block=vda'
    check "USB keyboard (USB_HID + xHCI)"   'input=QEMU QEMU USB Keyboard'
    check "USB tablet (absolute pointer)"   'input=QEMU QEMU USB Tablet'
    check "PS/2 keyboard (i8042/atkbd)"     'input=AT Translated Set 2 keyboard'
    check "PS/2 mouse (MOUSE_PS2)"          'input=.*PS/2.*Mouse'
    check "DRM device node (display works)" 'dri=card[0-9]+'
    check "DMI board_name readable (DMIID; Nightfall's rotation default)" 'dmi_board=NFBoard'
    check "lockdown LSM readable, mode none (securityfs; kexec preflight)" 'lockdown=.*\[none\].*'
    for fs in ext4 btrfs xfs f2fs vfat exfat ntfs3 iso9660 udf; do check "filesystem: $fs" "fs=$fs"; done
    if [ "$FAILS" -gt 0 ]; then
        echo "  -- facts the guest actually reported --"
        grep '^FACT' "$WORK/serial.log" | sed 's/^FACT /     /' | sort | tr '\n' ';' | fold -w 110 -s | sed 's/^/     /'; echo
    fi
}

FAILS=0
case "$MODES" in
    bios) run_mode bios ;;  uefi) run_mode uefi ;;  *) run_mode bios; run_mode uefi ;;
esac
echo; [ "$FAILS" -eq 0 ] && echo "SMOKE TEST PASSED" || echo "SMOKE TEST: $FAILS FAILURE(S)"
exit $(( FAILS > 0 ))

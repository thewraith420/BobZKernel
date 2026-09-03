#!/bin/bash
# Create portable kernel installer package for BobZKernel 7.2.
# Packages the built kernel + modules into a self-extracting tarball that
# auto-detects the target distro (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE)
# and runs the right initramfs/bootloader update steps.

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="7.2"
KERNEL_DIR="$BASE_DIR/builds/linux-$KERNEL_VERSION"

if [ ! -d "$KERNEL_DIR" ]; then
    echo -e "${RED}Error: $KERNEL_DIR not found. Run update-and-build-7.2.sh first.${NC}"
    exit 1
fi

if [ ! -f "$KERNEL_DIR/arch/x86/boot/bzImage" ]; then
    echo -e "${RED}Error: no bzImage in $KERNEL_DIR. Build the kernel first.${NC}"
    exit 1
fi

BRANCH=$(git -C "$BASE_DIR" branch --show-current 2>/dev/null || echo "master")

cd "$KERNEL_DIR"
# LOCALVERSION= keeps the resulting kernelrelease consistent with what was
# built (no spurious -dirty from setlocalversion looking at the patched tree).
KERNELRELEASE=$(make -s LOCALVERSION= kernelrelease 2>/dev/null)
if [ -z "$KERNELRELEASE" ]; then
    echo -e "${RED}Error: could not read kernelrelease from $KERNEL_DIR${NC}"
    exit 1
fi

# Determine the actual codegen target based on the branch we're building from.
# This matches the KCFLAGS logic in build-kernel-7.2.sh so the installer
# announces the same march= the kernel was actually compiled with.
case "$BRANCH" in
    pixel-slate|pixel-slate-7.2)
        MARCH_TARGET="-march=skylake -mtune=skylake"
        MARCH_OPTIMIZATION="march=skylake (Intel Skylake / Kaby Lake — Pixel Slate)"
        ARCH_NOTE="Built for Google Pixel Slate hardware (Skylake/Kaby Lake era Intel)."
        EXPECTED_VENDOR="GenuineIntel"
        EXPECTED_DESCRIPTION="Intel Skylake or newer (8th gen Y-series, Pixel Slate target)"
        ;;
    workpc)
        MARCH_TARGET="-march=bdver2 -mtune=bdver2"
        MARCH_OPTIMIZATION="march=bdver2 (AMD Piledriver / Bulldozer v2)"
        ARCH_NOTE="Built for AMD FX-series (Vishera/Piledriver) family 15h CPUs."
        EXPECTED_VENDOR="AuthenticAMD"
        EXPECTED_DESCRIPTION="AMD Family 15h+ (Bulldozer, Piledriver, Steamroller, Excavator, or Zen)"
        ;;
    generic-build)
        MARCH_TARGET="-march=x86-64-v2 -mtune=generic"
        MARCH_OPTIMIZATION="march=x86-64-v2 (universal modern x86-64 baseline)"
        ARCH_NOTE="Compatible with Intel Nehalem (2008+) and AMD Bulldozer (2011+) onwards."
        EXPECTED_VENDOR="any"
        EXPECTED_DESCRIPTION="Any x86-64 CPU with SSE4.2 + POPCNT (Intel 2008+, AMD 2011+)"
        ;;
    *)
        if grep -q "CONFIG_X86_NATIVE_CPU=y" .config; then
            MARCH_TARGET="-march=native"
            MARCH_OPTIMIZATION="march=native (CPU-specific — tuned to the build host's CPU)"
            ARCH_NOTE="Tuned for Intel Raptor Lake (13th Gen) — the laptop's CPU at build time."
            EXPECTED_VENDOR="GenuineIntel"
            EXPECTED_DESCRIPTION="Intel 12th-14th gen (Alder/Raptor Lake) — match the build host"
        else
            MARCH_TARGET="(unspecified)"
            MARCH_OPTIMIZATION="generic x86-64"
            ARCH_NOTE="Generic x86-64 build."
            EXPECTED_VENDOR="any"
            EXPECTED_DESCRIPTION="Any x86-64 CPU"
        fi
        ;;
esac
BUILD_HOST_CPU=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)

if grep -q "CONFIG_LTO_CLANG_FULL=y" .config; then
    LTO_STATUS="LTO Clang Full (whole-program Link Time Optimization)"
else
    LTO_STATUS="LTO disabled"
fi

if grep -q "CONFIG_SCHED_BORE=y" .config; then
    BORE_STATUS="BORE scheduler (Burst-Oriented Response Enhancer)"
else
    BORE_STATUS="Stock CFS/EEVDF scheduler"
fi

INSTALLER_DIR="$BASE_DIR/installer-$KERNELRELEASE"
# KERNELRELEASE is "7.2.1-BobZKernel" or "7.2.1-BobZKernel-workpc" etc.
# Strip the redundant "-BobZKernel" so the tarball is just
# "BobZKernel-7.2.1-installer.tar.gz" or "BobZKernel-7.2.1-workpc-installer.tar.gz".
PACKAGE_SLUG=${KERNELRELEASE/-BobZKernel/}
PACKAGE_NAME="BobZKernel-${PACKAGE_SLUG}-installer.tar.gz"

echo -e "${BLUE}Creating portable installer for $KERNELRELEASE${NC}"
echo

# Clean up old installer directory
if [ -d "$INSTALLER_DIR" ]; then
    echo -e "${YELLOW}Removing old installer directory...${NC}"
    rm -rf "$INSTALLER_DIR"
fi

echo -e "${BLUE}Creating installer directory structure...${NC}"
mkdir -p "$INSTALLER_DIR"/{boot,lib/modules}

echo -e "${BLUE}Copying kernel image, System.map, config...${NC}"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$INSTALLER_DIR/boot/vmlinuz-$KERNELRELEASE"
cp "$KERNEL_DIR/System.map" "$INSTALLER_DIR/boot/System.map-$KERNELRELEASE"
cp "$KERNEL_DIR/.config" "$INSTALLER_DIR/boot/config-$KERNELRELEASE"

echo -e "${BLUE}Installing modules into staging tree (this takes a minute)...${NC}"
cd "$KERNEL_DIR"
make LOCALVERSION= INSTALL_MOD_PATH="$INSTALLER_DIR" modules_install > /dev/null

echo -e "${BLUE}Compressing modules with zstd...${NC}"
find "$INSTALLER_DIR/lib/modules/$KERNELRELEASE" -name '*.ko' -exec zstd --rm -q -T0 {} \;

HEADERS_DEB=$(find "$BASE_DIR" -maxdepth 1 -name "linux-headers-${KERNELRELEASE}_*.deb" 2>/dev/null | head -1)
if [ -n "$HEADERS_DEB" ]; then
    echo -e "${BLUE}Bundling headers package for DKMS support: $(basename "$HEADERS_DEB")${NC}"
    cp "$HEADERS_DEB" "$INSTALLER_DIR/"
else
    echo -e "${YELLOW}⚠ No matching linux-headers-${KERNELRELEASE}_*.deb found - build-kernel-7.2.sh produces${NC}"
    echo -e "${YELLOW}  this alongside the kernel. Installer will work fine, just no DKMS support on the target.${NC}"
fi

echo -e "${BLUE}Writing VERSION manifest...${NC}"
cat > "$INSTALLER_DIR/VERSION" <<EOF
Kernel:        $KERNELRELEASE
Branch:        $BRANCH
Commit:        $(git -C "$BASE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
Built:         $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Build host:    $(uname -n)
Build CPU:     $BUILD_HOST_CPU

Features:
- $BORE_STATUS
- $MARCH_OPTIMIZATION
- $LTO_STATUS
- BBRv3 TCP congestion control (default)
- RSEQ slice extension (CONFIG_RSEQ_SLICE_EXTENSION=y, mainline)
- 9003-rseq-latency-histogram patch (abort latency stats)
- 9100-platform-profile-accept-custom patch (TLP can write 'custom' to
  /sys/firmware/acpi/platform_profile on Lenovo Legion/LOQ hardware)
- RANDSTRUCT Full

Note: $ARCH_NOTE
EOF

echo -e "${BLUE}Writing install.sh...${NC}"
# install.sh has two parts:
# (1) build-time-injected variables (expanding heredoc — $vars get filled in here)
# (2) the rest of the installer logic (single-quoted heredoc — preserved verbatim)
cat > "$INSTALLER_DIR/install.sh" <<EOF
#!/bin/bash
# BobZKernel 7.2 portable installer — variant: $BRANCH

# Build-time-injected values (set by create-portable-installer-7.2.sh):
BUILD_BRANCH="$BRANCH"
BUILD_MARCH_TARGET="$MARCH_TARGET"
BUILD_MARCH_DESCRIPTION="$MARCH_OPTIMIZATION"
EXPECTED_VENDOR="$EXPECTED_VENDOR"
EXPECTED_DESCRIPTION="$EXPECTED_DESCRIPTION"
EOF

cat >> "$INSTALLER_DIR/install.sh" <<'INSTALLER_SCRIPT'

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: must be run as root (use sudo).${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNELRELEASE=$(basename "$SCRIPT_DIR/boot"/vmlinuz-* 2>/dev/null | head -1 | sed 's/^vmlinuz-//')

if [ -z "$KERNELRELEASE" ] || [ ! -f "$SCRIPT_DIR/boot/vmlinuz-$KERNELRELEASE" ]; then
    echo -e "${RED}Error: could not locate kernel image in $SCRIPT_DIR/boot/${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         BobZKernel 7.2 Portable Installer            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Kernel: $KERNELRELEASE${NC}"
echo

if [ -f "$SCRIPT_DIR/VERSION" ]; then
    cat "$SCRIPT_DIR/VERSION"
    echo
fi

# Compatibility check — variant-aware. The EXPECTED_VENDOR and
# EXPECTED_DESCRIPTION variables are baked in at build time so the same
# install.sh code path works for every branch (laptop, workpc, pixel-slate,
# generic, etc.). Only warns if there's an actual mismatch; no spurious
# "Intel Raptor Lake" alarm on builds that target a different CPU class.
HOST_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk -F: '{print $2}' | xargs)
HOST_FAMILY=$(grep -m1 "cpu family" /proc/cpuinfo | awk -F: '{print $2}' | xargs)
echo -e "${BLUE}Host CPU vendor: ${HOST_VENDOR} (family ${HOST_FAMILY})${NC}"
echo -e "${BLUE}Kernel codegen:  ${BUILD_MARCH_DESCRIPTION}${NC}"
echo -e "${BLUE}Expected CPU:    ${EXPECTED_DESCRIPTION}${NC}"

if [ "$EXPECTED_VENDOR" != "any" ] && [ "$EXPECTED_VENDOR" != "$HOST_VENDOR" ]; then
    echo
    echo -e "${RED}WARNING: This kernel was built with ${BUILD_MARCH_TARGET}, expecting${NC}"
    echo -e "${RED}${EXPECTED_VENDOR} CPUs. Your CPU vendor is ${HOST_VENDOR}, which is likely${NC}"
    echo -e "${RED}to fail at boot or crash with SIGILL. Build from source for your hardware${NC}"
    echo -e "${RED}with: git checkout <branch> && ./scripts/update-and-build-7.2.sh${NC}"
    echo
    read -p "Proceed anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_NAME="$NAME"
    else
        echo -e "${RED}Error: cannot detect distribution.${NC}"
        exit 1
    fi
}

detect_bootloader() {
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    if command -v update-grub &>/dev/null || command -v grub-mkconfig &>/dev/null || command -v grub2-mkconfig &>/dev/null; then
        BOOTLOADER="grub"
    else
        BOOTLOADER="unknown"
    fi
}

install_kernel_files() {
    echo -e "${BLUE}Installing kernel files to /boot...${NC}"
    cp -v "$SCRIPT_DIR/boot/vmlinuz-$KERNELRELEASE"   /boot/
    cp -v "$SCRIPT_DIR/boot/System.map-$KERNELRELEASE" /boot/
    cp -v "$SCRIPT_DIR/boot/config-$KERNELRELEASE"     /boot/
    echo -e "${BLUE}Installing modules to /lib/modules/$KERNELRELEASE/...${NC}"
    cp -r "$SCRIPT_DIR/lib/modules/$KERNELRELEASE" /lib/modules/
    depmod -a "$KERNELRELEASE"
    echo -e "${GREEN}✓ Kernel + modules installed${NC}"

    HEADERS_DEB=$(find "$SCRIPT_DIR" -maxdepth 1 -name "linux-headers-*.deb" 2>/dev/null | head -1)
    if [ -n "$HEADERS_DEB" ]; then
        echo -e "${BLUE}Installing headers package (DKMS support): $(basename "$HEADERS_DEB")${NC}"
        if dpkg -i "$HEADERS_DEB"; then
            echo -e "${GREEN}✓ Headers installed - /lib/modules/$KERNELRELEASE/build now points at a real tree${NC}"
        else
            echo -e "${YELLOW}⚠ Headers package failed to install (kernel itself is fine) - check dpkg output above${NC}"
        fi
    fi
}

update_initramfs() {
    echo -e "${BLUE}Generating initramfs...${NC}"
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            update-initramfs -c -k "$KERNELRELEASE" ;;
        fedora|rhel|centos|rocky|almalinux)
            dracut --force "/boot/initramfs-$KERNELRELEASE.img" "$KERNELRELEASE" ;;
        arch|manjaro|endeavouros|cachyos)
            mkinitcpio -k "$KERNELRELEASE" -g "/boot/initramfs-$KERNELRELEASE.img" ;;
        opensuse*|sles)
            dracut --force "/boot/initrd-$KERNELRELEASE" "$KERNELRELEASE" ;;
        *)
            echo -e "${YELLOW}Unknown distro ($DISTRO_ID); generate initramfs manually.${NC}" ;;
    esac
    echo -e "${GREEN}✓ Initramfs generated${NC}"
}

update_bootloader() {
    echo -e "${BLUE}Updating GRUB...${NC}"
    if command -v update-grub &>/dev/null; then
        update-grub
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        echo -e "${YELLOW}Could not find a GRUB updater; update bootloader manually.${NC}"
    fi
    echo -e "${GREEN}✓ Bootloader updated${NC}"
}

detect_distro
detect_bootloader
echo -e "${GREEN}Distribution: $DISTRO_NAME ($DISTRO_ID $DISTRO_VERSION)${NC}"
echo -e "${GREEN}Boot Mode:    $BOOT_MODE${NC}"
echo -e "${GREEN}Bootloader:   $BOOTLOADER${NC}"
echo
read -p "Proceed with installation? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo -e "${YELLOW}Cancelled.${NC}"; exit 0; }

install_kernel_files
update_initramfs
update_bootloader

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation complete                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Reboot and pick '$KERNELRELEASE' from your GRUB menu.${NC}"
echo -e "${YELLOW}If you use DKMS modules (NVIDIA, VirtualBox, etc.), rebuild them${NC}"
echo -e "${YELLOW}for the new kernel:  sudo dkms autoinstall -k $KERNELRELEASE${NC}"
INSTALLER_SCRIPT

chmod +x "$INSTALLER_DIR/install.sh"

echo -e "${BLUE}Writing uninstall.sh...${NC}"
cat > "$INSTALLER_DIR/uninstall.sh" <<'UNINSTALL_SCRIPT'
#!/bin/bash
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: must be run as root.${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNELRELEASE=$(basename "$SCRIPT_DIR/boot"/vmlinuz-* 2>/dev/null | head -1 | sed 's/^vmlinuz-//')

echo -e "${YELLOW}This will remove kernel $KERNELRELEASE from /boot and /lib/modules.${NC}"
read -p "Are you sure? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

rm -fv "/boot/vmlinuz-$KERNELRELEASE" \
       "/boot/System.map-$KERNELRELEASE" \
       "/boot/config-$KERNELRELEASE" \
       "/boot/initrd.img-$KERNELRELEASE" \
       "/boot/initramfs-$KERNELRELEASE.img" 2>/dev/null || true
rm -rfv "/lib/modules/$KERNELRELEASE"

if   command -v update-grub      &>/dev/null; then update-grub
elif command -v grub-mkconfig    &>/dev/null; then grub-mkconfig    -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig   &>/dev/null; then grub2-mkconfig   -o /boot/grub2/grub.cfg
fi

echo -e "${GREEN}Kernel $KERNELRELEASE removed.${NC}"
UNINSTALL_SCRIPT

chmod +x "$INSTALLER_DIR/uninstall.sh"

echo -e "${BLUE}Writing README.md...${NC}"
cat > "$INSTALLER_DIR/README.md" <<README
# BobZKernel $KERNELRELEASE — Portable Installer

Pre-built Linux $KERNEL_VERSION kernel for Lenovo Legion / LOQ-class hardware,
tuned for Intel Raptor Lake (13th Gen). See the project at
https://github.com/thewraith420/BobZKernel for source and build scripts.

## Compatibility

This binary was built with **\`march=native\`** on a 13th Gen Raptor Lake CPU.
That means GCC/Clang were free to emit instructions specific to that
microarchitecture. As a practical matter:

| CPU                             | Works? |
|---------------------------------|--------|
| Intel 12th/13th/14th Gen        | Yes    |
| Intel 11th Gen (Tiger Lake)     | Probably (test on a non-critical box first) |
| Intel 10th Gen and older        | No — build from source |
| AMD (any)                       | No — build from source |

If your CPU isn't a recent Intel, **don't install this**. Build from source
instead — the build pipeline takes care of march=native auto-detection:

\`\`\`bash
git clone https://github.com/thewraith420/BobZKernel
cd BobZKernel
./scripts/update-and-build-7.2.sh
\`\`\`

## What's in this kernel

- **$BORE_STATUS**
- **$LTO_STATUS**
- **$MARCH_OPTIMIZATION**
- **BBRv3** TCP congestion control (default)
- **RSEQ slice extension** (mainline; observability at \`/sys/kernel/debug/rseq/stats\`)
- **9003-rseq-latency-histogram** patch — abort latency stats
- **9100-platform-profile-accept-custom** patch — lets TLP write \`custom\` to
  \`/sys/firmware/acpi/platform_profile\` on Lenovo Legion / LOQ hardware
- **RANDSTRUCT Full** — kernel struct layout randomization (security)

See \`VERSION\` for the exact commit, build host, and feature manifest.

## Install

\`\`\`bash
tar -xzf BobZKernel-*-installer.tar.gz
cd <extracted dir>
sudo ./install.sh
\`\`\`

The installer detects your distribution and bootloader and runs the right
\`update-initramfs\` / \`dracut\` / \`mkinitcpio\` plus \`update-grub\` for you.
Tested target families:

- Debian / Ubuntu / Linux Mint / Pop!_OS
- Fedora / RHEL / CentOS / Rocky / AlmaLinux
- Arch / Manjaro / EndeavourOS / CachyOS
- openSUSE / SLES

## DKMS modules (NVIDIA, etc.)

This tarball ships **only the kernel + in-tree modules**. Out-of-tree DKMS
modules (NVIDIA, VirtualBox, etc.) need to rebuild themselves against the new
kernel after install:

\`\`\`bash
sudo dkms autoinstall -k $KERNELRELEASE
\`\`\`

If you're on **Lenovo Legion / LOQ** hardware and want the LenovoLegionLinux
driver, install it from upstream **after** booting this kernel:

\`\`\`bash
git clone https://github.com/johnfanv2/LenovoLegionLinux
cd LenovoLegionLinux/kernel_module
sudo make dkms-install
\`\`\`

## NVIDIA + RANDSTRUCT

This kernel uses \`CONFIG_RANDSTRUCT_FULL=y\`. The NVIDIA driver needs a small
source patch (\`__no_randomize_layout\`) to build against RANDSTRUCT kernels —
without it you'll get a kernel panic on suspend. The fix is in the BobZKernel
repo at \`scripts/nvidia-randstruct-fix.sh\`; run that on the NVIDIA DKMS source
before \`dkms autoinstall\`.

## Uninstall

\`\`\`bash
sudo ./uninstall.sh
\`\`\`

Removes /boot files, /lib/modules tree, and regenerates GRUB.

## License

GPL-2.0 (Linux kernel license).
README

echo -e "${BLUE}Creating tarball: $PACKAGE_NAME${NC}"
cd "$BASE_DIR"
tar -czf "$PACKAGE_NAME" -C "$INSTALLER_DIR" .

PACKAGE_SIZE=$(du -h "$PACKAGE_NAME" | cut -f1)
PACKAGE_SHA=$(sha256sum "$PACKAGE_NAME" | awk '{print $1}')

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Portable installer created                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Package:  $PACKAGE_NAME${NC}"
echo -e "${GREEN}Size:     $PACKAGE_SIZE${NC}"
echo -e "${GREEN}SHA-256:  $PACKAGE_SHA${NC}"
echo -e "${GREEN}Location: $BASE_DIR/$PACKAGE_NAME${NC}"
echo
echo -e "${BLUE}To attach to a GitHub release:${NC}"
echo "  gh release create v$PACKAGE_SLUG \\"
echo "    --title 'BobZKernel v$PACKAGE_SLUG ($MARCH_OPTIMIZATION)' \\"
echo "    --notes-file <notes.md> \\"
echo "    \"$BASE_DIR/$PACKAGE_NAME\""

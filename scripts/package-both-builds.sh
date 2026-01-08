#!/bin/bash
# Package both march=native and generic builds into multi-arch installer
# Run this after building both kernel variants

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$BASE_DIR/builds/linux-6.18"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   BobZKernel Multi-Arch Installer Packager            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo

# Check if we have the generic build staged
if [ ! -d "/tmp/bobzkernel-builds/generic-staging" ]; then
    echo -e "${RED}Error: Generic build not found in /tmp/bobzkernel-builds/generic-staging${NC}"
    echo -e "${YELLOW}The generic build should already be staged there.${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Switching to march=native build...${NC}"
cd "$KERNEL_DIR"
./scripts/config --enable X86_NATIVE_CPU
./scripts/config --disable GENERIC_CPU
./scripts/config --set-str LOCALVERSION "-BobZKernel"
make LLVM=1 olddefconfig > /dev/null

echo -e "${GREEN}✓ Config switched to march=native${NC}"

echo -e "${YELLOW}Step 2: Rebuilding march=native kernel (incremental build)...${NC}"
make LLVM=1 -j$(nproc) 2>&1 | tail -20

# Verify the build after rebuilding
CURRENT_RELEASE=$(make LLVM=1 -s kernelrelease)
if [[ "$CURRENT_RELEASE" != "6.18.3-BobZKernel" ]]; then
    echo -e "${RED}Error: Build produced wrong version${NC}"
    echo -e "${RED}Current: $CURRENT_RELEASE, Expected: 6.18.3-BobZKernel${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Built: $CURRENT_RELEASE${NC}"

echo -e "${YELLOW}Step 3: Staging march=native build...${NC}"
mkdir -p /tmp/bobzkernel-builds/march-native-staging/{boot,lib/modules}
make INSTALL_MOD_PATH=/tmp/bobzkernel-builds/march-native-staging modules_install LLVM=1 > /dev/null 2>&1
cp arch/x86/boot/bzImage /tmp/bobzkernel-builds/march-native-staging/boot/vmlinuz-6.18.3-BobZKernel
cp System.map /tmp/bobzkernel-builds/march-native-staging/boot/System.map-6.18.3-BobZKernel
cp .config /tmp/bobzkernel-builds/march-native-staging/boot/config-6.18.3-BobZKernel

echo -e "${GREEN}✓ march=native build staged${NC}"

echo -e "${YELLOW}Step 4: Creating multi-arch installer...${NC}"

# Create temp directory for installer
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Package march-native build
cd /tmp/bobzkernel-builds/march-native-staging
cat > metadata.conf <<EOF
KERNELRELEASE=6.18.3-BobZKernel
BUILD_TYPE=march-native
ARCH_NAME=Intel Raptor Lake (13th Gen) - march=native
BUILD_DATE=$(date -u +%Y-%m-%d)
BUILD_HOST=$(hostname)
COMPILER=$(clang --version | head -1)
EOF
tar -czf "$TEMP_DIR/payload-march-native.tar.gz" .
NATIVE_SIZE=$(stat -c%s "$TEMP_DIR/payload-march-native.tar.gz")
echo -e "${GREEN}  march=native: $(numfmt --to=iec-i --suffix=B $NATIVE_SIZE)${NC}"

# Package generic build
cd /tmp/bobzkernel-builds/generic-staging
cat > metadata.conf <<EOF
KERNELRELEASE=6.18.3-BobZKernel-generic
BUILD_TYPE=generic
ARCH_NAME=Generic x86-64-v3 (Universal)
BUILD_DATE=$(date -u +%Y-%m-%d)
BUILD_HOST=$(hostname)
COMPILER=$(clang --version | head -1)
EOF
tar -czf "$TEMP_DIR/payload-generic.tar.gz" .
GENERIC_SIZE=$(stat -c%s "$TEMP_DIR/payload-generic.tar.gz")
echo -e "${GREEN}  generic: $(numfmt --to=iec-i --suffix=B $GENERIC_SIZE)${NC}"

INSTALLER_NAME="BobZKernel-6.18.3-multi-arch-installer.sh"

echo -e "${YELLOW}Step 5: Generating self-extracting installer...${NC}"

# Generate the installer with embedded payloads
cat > "$BASE_DIR/$INSTALLER_NAME" <<'INSTALLER_EOF'
#!/bin/bash
# BobZKernel Multi-Architecture Self-Extracting Installer
# Contains optimized builds for different CPU architectures

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

HAS_DIALOG=false
HAS_WHIPTAIL=false
GUI_TYPE="text"

detect_gui() {
    if command -v dialog &> /dev/null; then
        HAS_DIALOG=true
        GUI_TYPE="dialog"
    elif command -v whiptail &> /dev/null; then
        HAS_WHIPTAIL=true
        GUI_TYPE="whiptail"
    else
        GUI_TYPE="text"
    fi
}

msgbox() {
    local title="$1"
    local message="$2"
    case "$GUI_TYPE" in
        dialog) dialog --title "$title" --msgbox "$message" 15 70 ;;
        whiptail) whiptail --title "$title" --msgbox "$message" 15 70 ;;
        *) echo -e "${BLUE}=== $title ===${NC}"; echo "$message"; read -p "Press Enter..." ;;
    esac
}

yesno() {
    local title="$1"
    local message="$2"
    case "$GUI_TYPE" in
        dialog) dialog --title "$title" --yesno "$message" 12 70; return $? ;;
        whiptail) whiptail --title "$title" --yesno "$message" 12 70; return $? ;;
        *)
            echo -e "${YELLOW}$message${NC}"
            read -p "Continue? [y/N] " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]]
            return $?
            ;;
    esac
}

menu() {
    local title="$1"; shift
    local message="$1"; shift
    case "$GUI_TYPE" in
        dialog) dialog --title "$title" --menu "$message" 20 75 10 "$@" 2>&1 >/dev/tty ;;
        whiptail) whiptail --title "$title" --menu "$message" 20 75 10 "$@" 3>&1 1>&2 2>&3 ;;
        *)
            echo -e "${BLUE}=== $title ===${NC}"
            echo "$message"
            echo
            local i=1
            local -a opts=("$@")
            for ((j=0; j<${#opts[@]}; j+=2)); do
                echo "  $i) ${opts[$j+1]}"
                ((i++))
            done
            echo
            read -p "Select option (1-$((i-1))): " choice
            echo "${opts[$(((choice-1)*2))]}"
            ;;
    esac
}

infobox() {
    local message="$1"
    case "$GUI_TYPE" in
        dialog|whiptail) $GUI_TYPE --infobox "$message" 5 60 ;;
        *) echo -e "${BLUE}$message${NC}" ;;
    esac
}

detect_cpu() {
    local cpu_model=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    if echo "$cpu_model" | grep -qi "13th Gen"; then
        CPU_ARCH="raptor-lake"
        CPU_DESC="Intel 13th Gen (Raptor Lake)"
        RECOMMENDED_BUILD="1"
    elif echo "$cpu_model" | grep -qi "12th Gen"; then
        CPU_ARCH="alder-lake"
        CPU_DESC="Intel 12th Gen (Alder Lake)"
        RECOMMENDED_BUILD="1"
    else
        CPU_ARCH="generic"
        CPU_DESC="Other CPU"
        RECOMMENDED_BUILD="2"
    fi
}

extract_payload() {
    local build_type="$1"
    local extract_dir="$2"
    infobox "Extracting $build_type kernel package..."
    local payload_marker="__PAYLOAD_${build_type}_BEGINS__"
    local payload_start=$(awk "/${payload_marker}/ {print NR + 1; exit 0; }" "$0")
    if [ -z "$payload_start" ]; then
        echo -e "${RED}Error: Payload for $build_type not found!${NC}"
        return 1
    fi
    local next_marker=$(awk "NR > $payload_start && /__PAYLOAD_.*_BEGINS__/ {print NR - 1; exit 0; }" "$0")
    if [ -z "$next_marker" ]; then
        tail -n +${payload_start} "$0" | tar -xz -C "$extract_dir"
    else
        local line_count=$((next_marker - payload_start))
        tail -n +${payload_start} "$0" | head -n ${line_count} | tar -xz -C "$extract_dir"
    fi
}

install_kernel() {
    local temp_dir="$1"
    infobox "Installing kernel files..."
    if [ -f "$temp_dir/metadata.conf" ]; then
        source "$temp_dir/metadata.conf"
    else
        echo -e "${RED}Error: Metadata not found!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Installing BobZKernel $KERNELRELEASE${NC}"
    echo -e "${BLUE}Build: $ARCH_NAME${NC}"
    echo
    cp -v "$temp_dir/boot"/* /boot/
    cp -rv "$temp_dir/lib/modules"/* /lib/modules/
    infobox "Generating initramfs..."
    update-initramfs -c -k "$KERNELRELEASE"
    infobox "Updating bootloader..."
    if command -v update-grub &> /dev/null; then
        update-grub
    elif command -v grub-mkconfig &> /dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v grub2-mkconfig &> /dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
    echo -e "${GREEN}Installation complete!${NC}"
}

main() {
    clear
    detect_gui
    if [ "$EUID" -ne 0 ]; then
        msgbox "Error" "This installer must be run as root.\n\nPlease run: sudo $0"
        exit 1
    fi
    msgbox "BobZKernel Installer" "Welcome to BobZKernel 6.18.3!\n\nOptimized Linux kernel with:\n• BORE Scheduler\n• BBRv3 TCP\n• Full LTO\n• 1000Hz timer\n• Clang 20.1.2\n\nChoose your CPU architecture for best performance."
    detect_cpu
    msgbox "CPU Detection" "Detected: $CPU_DESC\n\nWe'll recommend the best build for your system."
    local selection
    if [ "$RECOMMENDED_BUILD" = "1" ]; then
        selection=$(menu "Select Build" "Choose kernel build:" \
            "1" "march=native (RECOMMENDED for Intel 12th/13th Gen)" \
            "2" "Generic x86-64-v3 (Compatible with all modern CPUs)" \
            "3" "Cancel")
    else
        selection=$(menu "Select Build" "Choose kernel build:" \
            "1" "march=native (Best for Intel 12th/13th Gen only)" \
            "2" "Generic x86-64-v3 (RECOMMENDED for compatibility)" \
            "3" "Cancel")
    fi
    case "$selection" in
        "1") BUILD_TYPE="march-native"; BUILD_NAME="march=native (Intel 12th/13th Gen)" ;;
        "2") BUILD_TYPE="generic"; BUILD_NAME="Generic x86-64-v3" ;;
        *) echo "Installation cancelled."; exit 0 ;;
    esac
    if ! yesno "Confirm" "Install: $BUILD_NAME\n\nYour current kernel remains bootable in GRUB.\n\nProceed?"; then
        echo "Installation cancelled."
        exit 0
    fi
    INSTALL_TEMP=$(mktemp -d)
    trap "rm -rf $INSTALL_TEMP" EXIT
    if ! extract_payload "$BUILD_TYPE" "$INSTALL_TEMP"; then
        msgbox "Error" "Failed to extract kernel package."
        exit 1
    fi
    install_kernel "$INSTALL_TEMP"
    msgbox "Success!" "BobZKernel installed successfully!\n\nNext steps:\n1. Reboot your system\n2. Select BobZKernel in GRUB\n3. Verify: uname -r\n\nIf issues occur, boot your old kernel from GRUB."
}

main
exit 0

INSTALLER_EOF

# Append payloads
echo "" >> "$BASE_DIR/$INSTALLER_NAME"
echo "# Embedded kernel payloads below" >> "$BASE_DIR/$INSTALLER_NAME"
echo "__PAYLOAD_march-native_BEGINS__" >> "$BASE_DIR/$INSTALLER_NAME"
cat "$TEMP_DIR/payload-march-native.tar.gz" >> "$BASE_DIR/$INSTALLER_NAME"
echo "" >> "$BASE_DIR/$INSTALLER_NAME"
echo "__PAYLOAD_generic_BEGINS__" >> "$BASE_DIR/$INSTALLER_NAME"
cat "$TEMP_DIR/payload-generic.tar.gz" >> "$BASE_DIR/$INSTALLER_NAME"

chmod +x "$BASE_DIR/$INSTALLER_NAME"

FINAL_SIZE=$(stat -c%s "$BASE_DIR/$INSTALLER_NAME")

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Multi-Arch Installer Created Successfully!     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Installer: ${NC}$INSTALLER_NAME"
echo -e "${BLUE}Total Size: ${NC}$(numfmt --to=iec-i --suffix=B $FINAL_SIZE)"
echo -e "${BLUE}Builds Included:${NC}"
echo -e "  • march=native (Intel 13th Gen)"
echo -e "  • Generic x86-64-v3"
echo
echo -e "${YELLOW}To distribute:${NC}"
echo -e "  scp $INSTALLER_NAME user@host:~/"
echo -e "  sudo ./$INSTALLER_NAME"
echo
echo -e "${GREEN}Cleaning up temporary files...${NC}"
rm -rf /tmp/bobzkernel-builds

echo -e "${GREEN}Done!${NC}"

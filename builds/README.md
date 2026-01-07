# Kernel Build Directory

This directory contains the Linux kernel source code. The kernel source is **not** tracked in git due to its size (~1GB).

## Getting the Kernel Source

The kernel source is automatically downloaded when you run:

```bash
./scripts/update-kernel-source.sh 6.18
```

This will:
1. Clone Linux 6.18 stable kernel from kernel.org
2. Place it in `builds/linux-6.18/`
3. Apply CachyOS performance patches
4. Ready to build

## Manual Setup

If you prefer to clone manually:

```bash
cd builds/
git clone --depth=1 --branch linux-6.18.y \
  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-6.18
```

Then apply patches and configure:

```bash
cd ..
./scripts/apply-patches.sh 6.18
cp configs/config-6.18.3-march-native builds/linux-6.18/.config
# or for generic:
# cp configs/config-6.18.3-generic builds/linux-6.18/.config
```

## Directory Contents (After Setup)

```
builds/
├── README.md          # This file
└── linux-6.18/        # Kernel source (not in git)
    ├── arch/
    ├── drivers/
    ├── kernel/
    ├── .config        # Kernel configuration
    └── ...
```

## Note

The kernel source directory (`linux-6.18/`) is in `.gitignore` to keep the repository size small. Only BobZKernel's custom scripts, configurations, and patches are tracked in git.

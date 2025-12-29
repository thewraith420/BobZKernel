# Building Your Current Kernel from Source

## Your Current Setup

- **Kernel Version:** 6.14.0
- **Saved Config:** `/home/bob/buildstuff/BobzKernel/configs/.config`
- **Source Location:** `/home/bob/buildstuff/BobzKernel/builds/linux`
- **Build Script:** `/home/bob/buildstuff/BobzKernel/scripts/build-kernel.sh`

## Build Process

### Step 1: Navigate to kernel source
```bash
cd ~/buildstuff/BobzKernel/builds/linux
```

### Step 2: Copy your saved configuration
```bash
cp ../configs/.config .config
make oldconfig  # Update config for new kernel (press Enter to accept defaults)
```

### Step 3: Build the kernel
```bash
# Option A: Use the build script
~/buildstuff/BobzKernel/scripts/build-kernel.sh .

# Option B: Manual build (4x parallelism)
make -j4
make modules -j4
```

### Step 4: Install
```bash
sudo make install
sudo make modules_install
```

### Step 5: Update bootloader and reboot
```bash
sudo update-grub    # Update GRUB configuration
sudo reboot         # Reboot and select your new kernel
```

## Verification

After reboot, verify your new kernel is running:
```bash
uname -r  # Should show a version close to 6.14
```

## Time Estimates

- Initial clone/download: 10-30 minutes (network dependent)
- First build: 30-60 minutes (depends on CPU cores)
- Subsequent builds: 5-10 minutes

## Troubleshooting

If the build fails:
1. Run `make mrproper` to clean everything
2. Re-copy your `.config` and try again
3. Check that all dependencies are installed:
   ```bash
   sudo apt-get install -y build-essential bc bison flex libelf-dev libssl-dev
   ```

## Tips

- The `-j` flag specifies parallel jobs. Use `-j$(nproc)` for all CPU cores
- Keep your original `.config` backed up (already done)
- First build takes longer because everything is new
- Later rebuilds are much faster

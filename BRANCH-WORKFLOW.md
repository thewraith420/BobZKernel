# Branch Workflow

## Branch Structure

- **master** - march=native build (Intel 13th Gen Raptor Lake optimized)
- **generic-build** - Generic x86-64-v3 build (universal compatibility)

## Building march=native (master branch)

```bash
git checkout master
cp configs/config-6.18.3-march-native builds/linux-6.18/.config
./scripts/build-kernel.sh
./scripts/create-self-extracting-installer.sh
```

Produces: `BobZKernel-6.18.3-BobZKernel-march-native-installer.sh`

## Building Generic (generic-build branch)

```bash
git checkout generic-build
cp configs/config-6.18.3-generic builds/linux-6.18/.config
./scripts/build-kernel.sh
# Edit create-self-extracting-installer.sh to set BUILD_TYPE="generic"
./scripts/create-self-extracting-installer.sh
```

Produces: `BobZKernel-6.18.3-BobZKernel-generic-generic-installer.sh`

## Important Notes

- **Never build both on the same branch** - source contamination can occur
- Always use the correct config file for each branch
- The kernel build artifacts in `builds/linux-6.18/` are branch-specific
- Installer files can be created after building on the respective branch

## Configuration Files

- `configs/config-6.18.3-march-native` - march=native configuration
- `configs/config-6.18.3-generic` - Generic x86-64-v3 configuration

Both configs include all optimizations (BORE, BBRv3, LTO, 1000Hz) - only the CPU target differs.

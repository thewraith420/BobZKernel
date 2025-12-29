# Contributing to BobZKernel

Thank you for your interest in contributing! This custom kernel configuration is optimized for the Lenovo LOQ 15IRH8, but the techniques can be adapted for other systems.

## How to Contribute

### Reporting Issues
- Use GitHub Issues to report bugs or suggest improvements
- Include your hardware specs (CPU, RAM, GPU)
- Provide kernel version and error messages
- Attach relevant logs (`dmesg`, `journalctl`)

### Submitting Changes
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-optimization`)
3. Make your changes
4. Test thoroughly (build, boot, verify)
5. Document your changes (update relevant docs)
6. Commit with clear messages
7. Push to your fork
8. Open a Pull Request

### Code Style
- **Scripts:** Follow existing bash style (shellcheck clean)
- **Documentation:** Use Markdown, keep it concise
- **Commits:** Use descriptive messages

### Testing Checklist
Before submitting:
- [ ] Kernel builds successfully
- [ ] Kernel boots without errors
- [ ] No regressions in existing features
- [ ] Documentation updated
- [ ] Changes tested on target hardware

## Areas for Contribution

### High Priority
- **Hardware Support:** Adapt for other Lenovo/Intel laptops
- **Scheduler Patches:** BORE, BMQ/PDS integration
- **LTO Support:** Clang LTO configuration
- **Benchmarks:** Performance comparisons

### Documentation
- **Guides:** Step-by-step for beginners
- **Troubleshooting:** Common issues and fixes
- **Translations:** Non-English documentation

### Testing
- Different kernel versions (6.x, 7.x)
- Different hardware configurations
- Battery life measurements
- Performance benchmarks

## Development Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/BobZKernel.git
cd BobZKernel

# Download kernel source
cd builds
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.14.tar.xz
tar -xf linux-6.14.tar.xz
mv linux-6.14 linux
cd ..

# Build
cd builds/linux
make KCONFIG_CONFIG=../../configs/.config LOCALVERSION=-BobZKernel -j$(nproc)

# Test (install at your own risk)
cd ../..
sudo ./scripts/install-kernel.sh
```

## Questions?

- Open a GitHub Discussion for general questions
- Check existing issues before creating new ones
- Read the documentation in `docs/`

## License

By contributing, you agree that your contributions will be licensed under the MIT License (for configs/scripts/docs) and GPL v2 (for kernel-related code).

---

**Thank you for making BobZKernel better!**

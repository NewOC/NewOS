# NewOS

![GitHub forks](https://img.shields.io/github/forks/NewOC/NewOS?style=social)
![GitHub last commit](https://img.shields.io/github/last-commit/NewOC/NewOS/main)
![GitHub Repo stars](https://img.shields.io/github/stars/NewOC/NewOS?style=social)
![GitHub License](https://img.shields.io/github/license/NewOC/NewOS)
![GitHub issues](https://img.shields.io/github/issues/NewOC/NewOS)

## 32-bit Protected Mode OS

NewOS is a simple operating system that successfully boots from 16-bit real mode into 32-bit protected mode with a working console!

### Features

- ✅ **Bootloader** - Loads from disk and switches to protected mode
- ✅ **32-bit Kernel** - Runs in x86 protected mode
- ✅ **VGA Text Driver** - Screen output with automatic scrolling
- ✅ **Keyboard Driver** - Full keyboard input support
- ✅ **Command Shell** - Interactive console with commands
- ✅ **Commands**: `help`, `clear`, `about`

### Building and Running

**Requirements:**
- NASM assembler
- QEMU emulator

**Build:**
```bash
.\build.bat
```

**Run:**
```bash
qemu-system-i386 -fda build\os-image.bin
```

### Available Commands

- `help` - Show available commands
- `clear` - Clear screen
- `about` - Show OS information

### Architecture

```
BIOS → Bootloader (16-bit) → Protected Mode Switch → Kernel (32-bit)
```

**Bootloader:**
- Loads kernel from disk
- Sets up GDT (Global Descriptor Table)
- Switches CPU to protected mode
- Jumps to kernel

**Kernel:**
- VGA text mode driver (0xb8000)
- Keyboard driver (ports 0x60/0x64)
- Command shell with input buffer
- Backspace and Enter support

### Roadmap

#### Console version (✅ Completed)
- [x] Kernel
- [x] Basic commands
- [x] Keyboard input
- [x] Screen management
- [ ] File system interaction
- [ ] Disk operations
- [ ] System information commands
- [ ] Package manager

#### Future improvements
- [ ] IDT (Interrupt Descriptor Table)
- [ ] Timer (PIT)
- [ ] Paging and virtual memory
- [ ] FAT12/FAT16 file system
- [ ] More shell commands
- [ ] Color support
- [ ] Multi-tasking

### Author

**MinecAnton209**

### License

See LICENSE file for details.

---

**Made with ❤️ in x86 Assembly**
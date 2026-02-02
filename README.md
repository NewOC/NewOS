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
- ✅ **32-bit Kernel** - Runs in x86 protected mode (Assembly + Zig)
- ✅ **IDT Support** - Interrupt Descriptor Table with exception handling
- ✅ **PIT Timer** - System timer (1kHz) for precise timing and uptime
- ✅ **VGA Text Driver** - Screen output with automatic scrolling
- ✅ **Keyboard Driver** - Full keyboard input support with interrupts
- ✅ **Command Shell** - Interactive console with history and scrolling
- ✅ **Nova Language** - Integrated custom interpreter

### Building and Running

**Requirements:**
- NASM assembler
- Zig compiler (latest)
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
- `about` - Show OS information (Version, Architecture)
- `nova` - Start Nova Language Interpreter
- `uptime` - Show system uptime in seconds
- `reboot` - Reboot system
- `shutdown` - Shutdown system
- `ls`, `touch`, `rm`, `cat`, `echo` - RAM file system commands

### Nova Language
A custom interpreted language built into NewOS.

**Features:**
- Variables: `set string name = "Value";`, `set int age = 20;`
- Arithmetic: `+`, `-`, `*`, `/`, `()` (e.g. `print((10+2)*5);`)
- System: `reboot();`, `shutdown();`

### Architecture

```
BIOS → Bootloader (16-bit) → Protected Mode Switch → Kernel (32-bit) → Zig Modules
```

**Bootloader:**
- Loads kernel from disk (50 sectors)
- Sets up GDT (Global Descriptor Table)
- Switches CPU to protected mode
- Jumps to kernel

**Kernel:**
- Written in x86 Assembly and Zig
- Interrupt management (IDT & PIC remapping)
- System timer (PIT) for precise delays
- VGA text mode driver (0xb8000)
- Keyboard driver (IRQ1 based)
- Command shell with history
- Integrated Nova Interpreter

### Roadmap

#### Current progress (v0.4)
- [x] IDT (Interrupt Descriptor Table)
- [x] Timer (PIT) & Precise Sleep
- [x] Command Uptime
- [x] Keyboard Interrupts
- [x] Basic commands & Screen management
- [x] File system interaction (Mock/RAM)
- [x] Nova Language
- [x] System control (reboot/shutdown)

#### Future improvements
- [ ] FAT12/FAT16 file system (Real disk support)
- [ ] Heap Memory Allocator (kmalloc/kfree)
- [ ] Paging & Virtual Memory Management
- [ ] Multi-tasking (Kernel & User threads)
- [ ] User Mode (Ring 3) & System Calls
- [ ] Graphic mode support (VBE/LFB)
- [ ] PS/2 Mouse Support
- [ ] PCI Bus Enumeration
- [ ] ATA/IDE Disk Driver
- [ ] Simple Sound Driver (PC Speaker)

### Author

**MinecAnton209**

### License

See LICENSE file for details.

---

**Made with ❤️ in x86 Assembly & Zig**
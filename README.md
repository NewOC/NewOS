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
- ✅ **RTC Driver** - Real-time clock support for date and time
- ✅ **VGA Text Driver** - Screen output with automatic scrolling and history
- ✅ **Keyboard Driver** - Full keyboard input support with interrupts (Shift, CAPS, NUM)
- ✅ **Command Shell** - Interactive console with **Tab Autocomplete**, **Command History** (persisted to disk), and cycling matches
- ✅ **FAT12/16 Support** - Native disk support for ATA drives
- ✅ **Nova Language v0.5** - Integrated custom interpreter with history and autocomplete

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
qemu-system-i386 -drive format=raw,file=build\os-image.bin -drive format=raw,file=disk.img
```

### Available Commands

- `help`           - Show available commands (auto-synced)
- `clear`          - Clear screen
- `about`          - Show OS information (Version, Architecture)
- `nova`           - Start Nova Language Interpreter
- `uptime`         - Show system uptime and current RTC time
- `time`           - Show current date and time
- `reboot`         - Reboot system
- `shutdown`       - Shutdown system (ACPI support)
- `ls`, `lsdsk`    - List files and disks
- `mount <d>`      - Select active disk (0/1 or ram)
- `touch <file>`   - Create file on disk/RAM
- `cat <file>`     - Show file contents
- `edit <file>`    - Open built-in text editor
- `rm <file>`      - Delete file
- `history`        - Show command history
- `mem`            - Test memory allocator

### Nova Language
A custom interpreted language built into NewOS. Now featuring **Command History** and **Tab Autocomplete**.

**Features:**
- Variables: `set string name = "Value";`, `set int age = 10 + 20;`
- Arithmetic: `+`, `-`, `*`, `/`, `()` (e.g. `print((10+2)*5);`)
- System: `reboot();`, `shutdown();`, `exit();`

### Architecture

```
BIOS → Bootloader (16-bit) → Protected Mode Switch → Kernel (32-bit) → Zig Modules
```

**Bootloader:**
- Loads kernel from disk
- Sets up GDT (Global Descriptor Table)
- Switches CPU to protected mode
- Jumps to kernel

**Kernel:**
- Written in x86 Assembly and Zig
- Interrupt management (IDT & PIC remapping)
- System timer (PIT) and Real-Time Clock (RTC)
- VGA text mode driver (0xb8000)
- Keyboard driver (IRQ1 based)
- Command shell with persistent history and autocomplete
- Integrated Nova Interpreter

### Roadmap

#### Current progress (v0.8)
- [x] IDT (Interrupt Descriptor Table)
- [x] Timer (PIT) & Precise Sleep
- [x] RTC Driver (Date/Time)
- [x] Keyboard Interrupts (Extended keys, Shift/Caps/Num)
- [x] Command Shell with **Tab Autocomplete**
- [x] Persistent command history on disk
- [x] FAT12/FAT16 file system (Real disk support)
- [x] Built-in Text Editor (`edit`)
- [x] Dynamic Shell Commands table
- [x] Nova Language v0.5 (History, Autocomplete)

#### Future improvements
- [ ] Heap Memory Allocator (kmalloc/kfree) - *In progress (v0.5)*
- [ ] Paging & Virtual Memory Management
- [ ] Multi-tasking (Kernel & User threads)
- [ ] User Mode (Ring 3) & System Calls
- [ ] Graphic mode support (VBE/LFB)
- [ ] PS/2 Mouse Support
- [ ] PCI Bus Enumeration
- [ ] Simple Sound Driver (PC Speaker)

### Author

**MinecAnton209**

### License

See LICENSE file for details.

---

**Made with ❤️ in x86 Assembly & Zig**
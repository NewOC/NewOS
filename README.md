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
- ✅ **Nova Language v0.10.5** - Integrated custom interpreter with history, autocomplete, math, and script support
- ✅ **Embedded Scripts** - Built-in commands written in Nova (`syscheck`, `hello`, `install`)
- ✅ **Recursive FS** - `cp` and `delete` now support recursive directory operations

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
- `syscheck`       - Run system health check (Embedded Nova Script)
- `uptime`         - Show system uptime and current RTC time
- `time`           - Show current date and time
- `reboot`         - Reboot system
- `shutdown`       - Shutdown system (ACPI support)
- `ls`, `lsdsk`    - List files and disks
- `mount <d>`      - Select active disk (0/1 or ram)
- `touch <file>`   - Create file on disk/RAM
- `mkdir <dir>`    - Create directory
- `cp <src> <dst>` - Copy file or **folder recursively**
- `mv <src> <dst>` - Move or rename file/folder
- `cat <file>`     - Show file contents
- `edit <file>`    - Open built-in text editor
- `rm <file>`      - Delete file/folder (recursive support)
- `history`        - Show command history
- `mem`            - Test memory allocator

### Nova Language
A custom interpreted language built into NewOS. Now featuring **Command History**, **Tab Autocomplete**, and **Embedded Scripts**.

**Features:**
- Variables: `set string name = "Value";`, `set int age = 10 + 20;`
- Arithmetic: `+`, `-`, `*`, `/`, `^`, `%`, `()` (e.g. `print((10+2)*5);`)
- Math: `sin()`, `cos()`, `tan()`, `abs()`, `min()`, `max()`, `random()`
- Filesystem: `create_file`, `write_file`, `mkdir`, `delete`, `copy`, `rename`, `read`
- Interactive: `input()` for reading user input
- System: `reboot();`, `shutdown();`, `exit();`
- Scripting: `argc()`, `args(n)`, `install("script.nv")`

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

#### Current progress (v0.10.1)
- [x] IDT (Interrupt Descriptor Table)
- [x] Timer (PIT) & Precise Sleep
- [x] RTC Driver (Date/Time)
- [x] Keyboard Interrupts (Extended keys, Shift/Caps/Num)
- [x] Command Shell with **Tab Autocomplete**
- [x] Persistent command history on disk
- [x] FAT12/FAT16 file system (Real disk support)
- [x] Recursive Directory Operations (cp, rm)
- [x] Built-in Text Editor (`edit`)
- [x] Dynamic Shell Commands table
- [x] Nova Language v0.10 (History, Autocomplete, Sci-Math, Scripts)
- [x] Embedded Nova Commands (syscheck, install)

#### Future improvements
- [x] Heap Memory Allocator (kmalloc/kfree) - *Basic implementation done*
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
# NewOS Commands Reference (v0.10)

## System Control
| Command | Description | Usage |
|---------|-------------|-------|
| `help` | Show command list | `help` |
| `docs` | Show detailed documentation | `docs` |
| `about` | About NewOS | `about` |
| `sysinfo` | Show hardware/OS info | `sysinfo` |
| `uptime` | Show system uptime | `uptime` |
| `time` | Show RTC time | `time` |
| `reboot` | Restart computer | `reboot` |
| `shutdown` | Power off (ACPI) | `shutdown` |
| `clear` | Clear the screen | `clear` |

## File System Navigation & Management
| Command | Description | Usage |
|---------|-------------|-------|
| `ls` | List files and folders | `ls [path]` |
| `cd` | Change current directory | `cd <dir\|..\|/>` |
| `lsdsk` | List disks and partitions | `lsdsk` |
| `mount` | Change active drive | `mount <0/1>` |
| `mkdir` | Create new directory | `mkdir <name>` |
| `md` | Alias for `mkdir` | `md <name>` |
| `tree` | Show directory structure | `tree` |
| `touch` | Create an empty file | `touch <file_path>` |
| `write` | Write text to a file | `write <file_path> <text>` |
| `cat` | View file content | `cat <file_path>` |
| `cp` | Copy file | `cp <src> <dest>` |
| `mv` | Move or rename file | `mv <src> <dest>` |
| `ren` | Alias for `mv` (rename) | `ren <old> <new>` |
| `rm` | Delete file/directory | `rm [-d] [-r] <file\|*>` |

### `rm` Command Details:
- `-d`: Remove empty directory.
- `-r`: Recursive removal (deletes non-empty directories).
- `*`: Wildcard (requires `-dr` and `--yes-i-am-sure` to delete everything in current folder).

## Tools & Development
| Command | Description | Usage |
|---------|-------------|-------|
| `edit` | Primitive text editor | `edit <file_path>` |
| `nova` | Start Nova Scripting Shell | `nova` |
| `mem` | Show memory heap status | `mem` |
| `history` | Show command history | `history` |
| `echo` | Print text to console | `echo <text>` |

## Advanced Formatting
| Command | Description | Usage |
|---------|-------------|-------|
| `format` | Low-level disk format | `format <drive>` |
| `mkfs` | Create FAT filesystem | `mkfs [type]` |

---
*Note: All file system commands support nested paths (e.g., `ls 123/`, `touch data/test.txt`).*

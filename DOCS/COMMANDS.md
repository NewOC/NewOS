# NewOS Commands Reference (v0.10)

Comprehensive documentation for all built-in NewOS shell commands.

---

## 🚀 Quick Reference Table

| Command | Description | Usage |
|---------|-------------|-------|
| `help` | Show command list | `help [page]` |
| `ls` | List files/folders | `ls [path]` |
| `cd` | Change directory | `cd <dir|..|/>` |
| `mkdir` | Create directory | `mkdir <name>` |
| `touch` | Create empty file | `touch <path>` |
| `edit` | Text editor | `edit <path>` |
| `write` | Write text to file | `write <path> <text>` |
| `cat` | View file content | `cat <path>` |
| `rm` | Delete file/dir | `rm [-d] [-r] <f|*>` |
| `cp` | Copy file | `cp <src> <dest>` |
| `mv` | Move/Rename | `mv <src> <dest>` |
| `tree` | Directory tree | `tree` |
| `sysinfo` | System info | `sysinfo` |
| `uptime` | System uptime | `uptime` |
| `mem` | Memory status | `mem` |
| `nova` | Nova Interpreter | `nova` |
| `reboot` | Restart system | `reboot` |
| `shutdown` | Power off | `shutdown` |

---

## 🛠 System Control

### `help`
Displays a list of available commands.
- **Usage:** `help [page]`
- **Note:** Use `help 2` to see the second page of commands.

### `clear`
Clears the console screen and resets the cursor position to the top-left.
- **Usage:** `clear`

### `about`
Displays legal information, versioning details, and the creator credits.
- **Usage:** `about`

### `sysinfo`
Displays hardware information, CPU details, and OS build identity.
- **Usage:** `sysinfo`

### `uptime`
Shows how long the system has been running since the last boot.
- **Usage:** `uptime`

### `time`
Displays the current Real-Time Clock (RTC) date and time.
- **Usage:** `time`

### `reboot`
Safely restarts the computer using the keyboard controller pulse.
- **Usage:** `reboot`

### `shutdown`
Powers off the system using ACPI commands.
- **Usage:** `shutdown`

---

## 📁 File System Navigation

### `ls`
Lists files and directories in the target path or current directory.
- **Usage:** `ls [path]`
- **Examples:**
  - `ls` (Current directory)
  - `ls 123/` (Contents of folder '123')
  - `ls /` (Root directory)

### `cd`
Changes the current working directory.
- **Usage:** `cd <dir|..|/>`
- **Navigation:**
  - `cd folder` - Enter a directory.
  - `cd ..` - Go to the parent directory.
  - `cd /` - Return to the root directory.
- **Easter Eggs:**
  - Try `cd .` or `cd ..` while already in the root!

### `lsdsk`
Lists all detected storage devices (Master/Slave) and their capacity.
- **Usage:** `lsdsk`

### `mount`
Selects which disk drive is currently active for file operations.
- **Usage:** `mount <0|1>`
- **0:** Master Drive
- **1:** Slave Drive

### `mkdir` (alias: `md`)
Creates a new directory in the current path.
- **Usage:** `mkdir <name>`
- **Example:** `mkdir documents`

### `tree`
Visualizes the entire directory structure starting from the current location.
- **Usage:** `tree`

---

## 📄 File Manipulation

### `touch`
Creates a new empty file at the specified path.
- **Usage:** `touch <file_path>`
- **Example:** `touch logs/boot.log`

### `write`
Writes a string of text into a file.
- **Usage:** `write <file_path> <text>`
- **Note:** This overwrites the existing content.
- **Example:** `write hello.txt "Hello World"`

### `cat`
Displays the text content of a file on the screen.
- **Usage:** `cat <file_path>`

### `rm`
Deletes files or directories.
- **Usage:** `rm [-d] [-r] <file|*>`
- **Flags:**
  - `-d`: Required to delete a directory. It must be empty.
  - `-r`: Recursive. Deletes a directory and everything inside it.
- **Wildcards:**
  - `rm *` is a protected operation. 
  - To wipe a folder completely, you **must** use: `rm -dr * --yes-i-am-sure`

### `cp`
Copies a file from one path to another.
- **Usage:** `cp <src> <dest>`

### `mv` (alias: `ren`)
Moves or renames a file/directory.
- **Usage:** `mv <src> <dest>`
- **Example:** `ren old.txt new.txt`

---

## 🔧 Tools & Utilities

### `edit`
Starts the primitive text editor to create or modify text files.
- **Usage:** `edit <file_path>`

### `nova`
Launches the Nova Scripting Interpreter for running scripts.
- **Usage:** `nova`

### `mem`
Displays the current status of the System Heap and memory allocator.
- **Usage:** `mem`

### `history`
Lists the most recently executed commands.
- **Usage:** `history`

### `echo`
Prints the provided text back to the console.
- **Usage:** `echo <text>`

---

## 📀 Formatting

### `format`
Performs a low-level format of the selected drive.
- **Usage:** `format <drive>`
- **WARNING:** Irreversible data loss.

### `mkfs`
Creates a FAT filesystem on the target drive.
- **Usage:** `mkfs-fat16 0` (Formats Master as FAT16)

---
*Generated for NewOS v0.10*

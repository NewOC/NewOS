; NewOS Kernel - 32-bit Protected Mode
; Main entry point and module includes
[bits 32]

; Put entry point in .text.start section to ensure it's first
section .text.start
global start

; Constants
VIDEO_MEMORY equ 0xb8000
MAX_COLS equ 80
MAX_ROWS equ 25
WHITE_ON_BLACK equ 0x0f
GREEN_ON_BLACK equ 0x0a
HISTORY_SIZE equ 10

; Special key codes
KEY_UP equ 0x80
KEY_DOWN equ 0x81
KEY_LEFT equ 0x82
KEY_RIGHT equ 0x83

section .data
; BSS - Variables
cursor_row db 0
cursor_col db 0
shift_state db 0
extended_key db 0
cmd_buffer times 128 db 0
cmd_len db 0
cmd_pos db 0

; Command history
history times 1280 db 0
history_lens times 10 db 0
history_count db 0
history_index db 0

section .text
; External Zig initialization
extern zig_init
extern kmain

; Entry point
start:
    mov esp, 0x90000
    mov ebp, esp
    
    call clear_screen
    
    ; Initialize Zig modules (file system)
    call zig_init
    
    mov esi, welcome
    call print_string
    
    mov esi, help_msg
    call print_string

    ; Transfer control to Zig Kernel
    call kmain
    
    ; Should never return
    cli
    hlt
    jmp $

; Include modules
%include "drivers/screen.asm"
%include "drivers/keyboard.asm"
%include "shell/shell.asm"
%include "data.asm"

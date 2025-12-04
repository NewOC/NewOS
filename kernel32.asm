; NewOS Kernel - 32-bit Protected Mode
; Main entry point and module includes
[org 0x1000]
[bits 32]

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

; Entry point
start:
    call clear_screen
    
    mov esi, welcome
    call print_string
    
    mov esi, help_msg
    call print_string

main_loop:
    mov esi, prompt
    call print_string
    
    call read_command
    call execute_command
    jmp main_loop

; Include modules
%include "drivers/screen.asm"
%include "drivers/keyboard.asm"
%include "shell/shell.asm"
%include "data.asm"
%include "lang/nova.asm"

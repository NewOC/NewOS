[bits 16]
[org 0x8000]

kernel_main:
    mov si, kernel_msg
    call print_string
.kernel_loop:
    call get_input
    call process_command
    jmp .kernel_loop

%include "print.asm"
%include "memory.asm"

input_buffer times 64 db 0
input_length db 0

kernel_msg db 'Kernel loaded!', 0
prompt_msg db '> ', 0

get_input:
    mov si, prompt_msg
    call print_string
    mov di, input_buffer
    mov byte [input_length], 0

.input_loop:
    mov ah, 0x00
    int 0x16

    cmp al, 0x0D
    je .input_done

    cmp al, 0x08
    je .backspace

    
    stosb
    inc byte [input_length]

    
    mov ah, 0x0E
    int 0x10
    jmp .input_loop

.backspace:
    cmp byte [input_length], 0
    je .input_loop
    dec di
    dec byte [input_length]
    
    
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .input_loop

.input_done:
    mov al, 0
    stosb
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ret

process_command:
    
    mov si, input_buffer
    

    
    
    mov di, cmd_help
    call strcmp
    je .show_help
    
    
    mov si, unknown_cmd_msg
    call print_string
    ret
    

    
.show_help:
    mov si, help_msg
    call print_string
    ret
    
strcmp:
    pusha

.compare_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc si
    inc di
    jmp .compare_loop

.equal:
    popa
    xor ax, ax
    ret

.not_equal:
    popa
    mov ax, 1
    ret

cmd_help db 'help', 0

unknown_cmd_msg db 'Unknown command', 0x0D, 0x0A, 0

help_msg db 'Available commands:', 0x0D, 0x0A
         db 'help - Show this help', 0x0D, 0x0A, 0
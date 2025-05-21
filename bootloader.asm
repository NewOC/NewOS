[bits 16]
[org 0x7c00]

boot_start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00

        mov si, welcome_msg
    call print_string

        mov bx, 0x8000
    mov dh, 0x01
    mov dl, 0x00
    call disk_load

        jmp 0x8000

%include "disk.asm"
%include "print.asm"

welcome_msg db 'Loading OS...', 0

times 510-($-$$) db 0
dw 0xaa55
[bits 16]
[org 0x7c00]

KERNEL_OFFSET equ 0x1000

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    
    mov [BOOT_DRIVE], dl
    
    ; Load kernel from disk
    mov bx, KERNEL_OFFSET
    mov dh, 10
    mov dl, [BOOT_DRIVE]
    
    ; Reset disk
    mov ah, 0x00
    int 0x13
    
    ; Read sectors
    mov ah, 0x02
    mov al, 10
    mov ch, 0x00
    mov cl, 0x02
    mov dh, 0x00
    mov dl, [BOOT_DRIVE]
    int 0x13
    
    ; Clear screen (BIOS interrupt)
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    
    ; Switch to protected mode
    cli
    lgdt [gdt_descriptor]
    
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    jmp 0x08:init_pm

[bits 32]
init_pm:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    mov ebp, 0x90000
    mov esp, ebp
    
    jmp KERNEL_OFFSET

; GDT
gdt_start:
    dq 0

gdt_code:
    dw 0xffff
    dw 0
    db 0
    db 10011010b
    db 11001111b
    db 0

gdt_data:
    dw 0xffff
    dw 0
    db 0
    db 10010010b
    db 11001111b
    db 0

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

BOOT_DRIVE: db 0

times 510-($-$$) db 0
dw 0xaa55
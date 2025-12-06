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
    
    ; Reset disk
    mov ah, 0x00
    mov dl, [BOOT_DRIVE]
    int 0x13
    
    ; Load kernel (50 sectors safe loop)
    mov bx, KERNEL_OFFSET
    mov bp, 50              ; Number of sectors to read
    
    mov dh, 0               ; Head
    mov ch, 0               ; Cylinder
    mov cl, 2               ; Sector
    
read_loop:
    mov ah, 0x02
    mov al, 1
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    add bx, 512
    dec bp
    jz read_done
    
    inc cl
    cmp cl, 19
    jl read_loop
    
    mov cl, 1
    inc dh
    cmp dh, 2
    jl read_loop
    
    mov dh, 0
    inc ch
    jmp read_loop
    
disk_error:
    jmp $

read_done:
    
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
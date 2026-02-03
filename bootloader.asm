; NewOS Bootloader - 16-bit Real Mode
; This code is located in the first sector of the disk (MBR).
; It loads the kernel from disk, switches to 32-bit Protected Mode, and jumps to kernel.

[bits 16]
[org 0x7c00]

; Memory offset where kernel will be loaded
KERNEL_OFFSET equ 0x10000

start:
    ; 1. Initialize segment registers and stack
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    
    ; 2. Save boot drive index (provided by BIOS in DL)
    mov [BOOT_DRIVE], dl
    
    ; 3. Reset disk controller
    mov ah, 0x00
    mov dl, [BOOT_DRIVE]
    int 0x13
    
    ; 4. Load kernel from disk
    ; We load 60 sectors (about 30KB) starting from sector 2
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    
    mov ah, 0x02            ; Read sectors
    mov al, 127             ; Number of sectors to read
    mov ch, 0               ; Cylinder 0
    mov dh, 0               ; Head 0
    mov cl, 2               ; Start from sector 2
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    jmp read_done
    
disk_error:
    ; Loop forever on error
    jmp $

read_done:
    ; 5. Clear screen before OS start
    mov ah, 0x00
    mov al, 0x03            ; 80x25 Color Text Mode
    int 0x10
    
    ; 6. Switch to 32-bit Protected Mode
    cli                     ; Disable interrupts
    lgdt [gdt_descriptor]   ; Load Global Descriptor Table
    
    mov eax, cr0
    or eax, 1               ; Set PE (Protection Enable) bit
    mov cr0, eax
    
    ; 7. Far jump to 32-bit segment (flushes CPU pipeline)
    jmp 0x08:init_pm

[bits 32]
init_pm:
    ; 8. Setup 32-bit data segments
    mov ax, 0x10            ; Data segment selector
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; 9. Setup high memory stack
    mov ebp, 0x90000
    mov esp, ebp
    
    ; 10. Jump to Loaded Kernel
    jmp KERNEL_OFFSET

; --- Global Descriptor Table (GDT) ---

gdt_start:
    dq 0                    ; Null descriptor

; Code segment descriptor
gdt_code:
    dw 0xffff               ; Limit (0-15 bits)
    dw 0                    ; Base (0-15 bits)
    db 0                    ; Base (16-23 bits)
    db 10011010b            ; Access byte
    db 11001111b            ; Flags + Limit (16-19 bits)
    db 0                    ; Base (24-31 bits)

; Data segment descriptor
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

; Boot signature
times 510-($-$$) db 0
dw 0xaa55
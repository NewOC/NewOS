; Trampoline for AP (Application Processor) Bootup
; This code runs in 16-bit Real Mode at 0x8000

[bits 16]
section .text
global trampoline_start
global trampoline_end

trampoline_start:
    cli
    cld
    xor ax, ax
    mov ds, ax

    ; Load GDT (defined below)
    ; We use absolute address because we know we are at 0x8000
    lgdt [gdt_descriptor_ap - trampoline_start + 0x8000]

    ; Enable Protected Mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Long jump to 32-bit code
    jmp 0x08:(trampoline_pm - trampoline_start + 0x8000)

[bits 32]
trampoline_pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    ; Load stack pointer from fixed location
    mov esp, [ap_stack_ptr - trampoline_start + 0x8000]

    ; Call AP entry point in Zig
    mov eax, [ap_main_ptr - trampoline_start + 0x8000]
    call eax

    ; Should not return
.halt:
    hlt
    jmp .halt

align 16
gdt_ap:
    dq 0                        ; Null
    dw 0xffff, 0x0000, 0x9a00, 0x00cf ; Code (0x08)
    dw 0xffff, 0x0000, 0x9200, 0x00cf ; Data (0x10)
gdt_ap_end:

gdt_descriptor_ap:
    dw gdt_ap_end - gdt_ap - 1
    dd gdt_ap - trampoline_start + 0x8000

; These will be filled by the Master core before sending SIPI
align 4
ap_stack_ptr dd 0
ap_main_ptr  dd 0

trampoline_end:

; IDT (Interrupt Descriptor Table) Management
; Sets up the CPU interrupt table, PIC remap, and basic ISR wrappers.

[bits 32]

global idt_init
global load_idt
global enable_interrupts
global disable_interrupts
global test_divide_by_zero

; External Zig ISR handlers
extern isr_keyboard
extern isr_timer
extern lapic_eoi


section .data
align 16
; Space for 256 gates (8 bytes each)
idt_start:
    times 256 * 8 db 0
idt_end:

section .data
align 4
; IDT Pointer for LIDT instruction
global kernel_idt_descriptor
kernel_idt_descriptor:
    dw idt_end - idt_start - 1
    dd idt_start

section .text

load_idt:
    lidt [kernel_idt_descriptor]
    ret

; Initialize the IDT and configure PIC
idt_init:
    pusha
    
    ; 1. Set default exception handler for all 256 gates
    mov ebx, 0
.loop_idt:
    mov eax, exception_handler_wrapper
    call idt_set_gate
    inc ebx
    cmp ebx, 256
    jl .loop_idt

    ; 2. Set special handler for Division by Zero (INT 0)
    mov eax, division_by_zero_handler
    mov ebx, 0
    call idt_set_gate

    ; 3. Remap the PIC (offset IRQs to 0x20+)
    call remap_pic
        
    ; 4. Mask all interrupts except Keyboard
    mov al, 0xff
    out 0x21, al
    out 0xa1, al

    ; 5. Set Timer ISR (IRQ0 -> 0x20)
    mov eax, isr_timer_wrapper
    mov ebx, 0x20
    call idt_set_gate

    ; 6. Set Keyboard ISR (IRQ1 -> 0x21)
    mov eax, isr_keyboard_wrapper
    mov ebx, 0x21
    call idt_set_gate
    
    ; 6. Load IDT into CPU
    lidt [kernel_idt_descriptor]

    ; Flush keyboard buffer
    in al, 0x60
    
    ; 7. Unmask IRQ0 (Timer) and IRQ1 (Keyboard)
    in al, 0x21
    and al, 0xfc        ; 11111100b - Unmask IRQ0 and IRQ1
    out 0x21, al

    
    popa
    ret

; Helper: Set a single IDT gate
; EAX: offset of handler, EBX: gate index
idt_set_gate:
    push edi
    
    mov edi, idt_start
    shl ebx, 3          ; index * 8
    add edi, ebx
    
    mov [edi], ax       ; Offset low 16 bits
    mov word [edi + 2], 0x08 ; Selector (Kernel Code)
    mov byte [edi + 4], 0    ; Reserved
    mov byte [edi + 5], 0x8E ; IDT attributes (Present, 32bit Interrupt Gate)
    shr eax, 16
    mov [edi + 6], ax   ; Offset high 16 bits
    
    pop edi
    ret

; ISR Wrapper: Keyboard (IRQ1)
isr_keyboard_wrapper:
    pushad
    
    ; Ensure segment registers are set to kernel data
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    cld                 ; Clear direction flag for Zig
    
    call isr_keyboard   ; Call actual logic in keyboard_isr.zig
    
    ; Send End Of Interrupt (EOI) to APIC
    call lapic_eoi
    
    popad
    iret

; ISR Wrapper: Timer (IRQ0)
isr_timer_wrapper:
    pushad
    
    ; Ensure segment registers are set to kernel data
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    cld                 ; Clear direction flag for Zig
    
    call isr_timer      ; Call actual logic in timer.zig
    
    ; Send End Of Interrupt (EOI) to APIC
    call lapic_eoi
    
    popad
    iret


extern kernel_panic

section .data
msg_div_zero db "Division By Zero Exception!", 0
msg_div_zero_len equ $ - msg_div_zero

msg_general_ex db "Unhandled CPU Exception!", 0
msg_general_ex_len equ $ - msg_general_ex

section .text
; General Exception Handler - Calls Kernel Panic
exception_handler_wrapper:
    cli
    push dword msg_general_ex_len
    push dword msg_general_ex
    call kernel_panic
    hlt
    jmp $

; Division by Zero Handler - Calls Kernel Panic
division_by_zero_handler:
    cli
    push dword msg_div_zero_len
    push dword msg_div_zero
    call kernel_panic
    hlt
    jmp $

; Test function to trigger division by zero exception
test_divide_by_zero:
    push ebp
    mov ebp, esp
    
    ; Trigger division by zero
    xor edx, edx
    xor eax, eax
    mov ecx, 0
    div ecx                     ; This will trigger INT 0
    
    ; Should never reach here
    mov esp, ebp
    pop ebp
    ret

; Remap the Programmable Interrupt Controller
; This prevents hardware IRQs from conflicting with CPU exceptions (0..31)
remap_pic:
    push eax
    mov al, 0x11
    out 0x20, al        ; ICW1 Master
    call io_wait
    out 0xA0, al        ; ICW1 Slave
    call io_wait
    mov al, 0x20
    out 0x21, al        ; ICW2 Master Offset 0x20
    call io_wait
    mov al, 0x28
    out 0xA1, al        ; ICW2 Slave Offset 0x28
    call io_wait
    mov al, 0x04
    out 0x21, al        ; ICW3 Master (Slave at IRQ2)
    call io_wait
    mov al, 0x02
    out 0xA1, al        ; ICW3 Slave (Identity)
    call io_wait
    mov al, 0x01
    out 0x21, al        ; ICW4 8086 mode
    call io_wait
    out 0xA1, al
    call io_wait
    pop eax
    ret

; IO Delay
io_wait:
    out 0x80, al
    ret

enable_interrupts:
    sti
    ret

disable_interrupts:
    cli
    ret
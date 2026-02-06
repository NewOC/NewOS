[bits 32]

global switch_context
global start_task_asm

; switch_context(current_context_ptr_ptr: **usize, next_context_ptr: usize)
; current_context_ptr_ptr: [ESP + 4]  - Address of the context_ptr field in current Task struct
; next_context_ptr:        [ESP + 8]  - Value of the context_ptr in next Task struct

switch_context:
    ; 1. Manual switch: push fake IRET frame to match interrupt context
    pushfd                  ; EFLAGS
    push dword 0x08         ; CS
    push dword .manual_exit ; EIP
    
    pushad                  ; Save EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI

    ; 2. Store current ESP into current_context_ptr_ptr
    mov eax, [esp + 32 + 12 + 4] ; Account for pushad(32) + iret_frame(12) + retaddr(4)
    mov [eax], esp

    ; 3. Switch to next stack
    mov esp, [esp + 32 + 12 + 8]

    ; 4. Restore context
    popad
    iret

.manual_exit:
    ret

; Used to launch the first task on a core
start_task_asm:
    mov esp, [esp + 4]      ; Load task context pointer
    popad                   ; Restore EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX
    iret                    ; Return to EIP via EFLAGS, CS, EIP frame

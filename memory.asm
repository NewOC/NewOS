mem_init:
        xor dx, dx
    int 0x12
    mov dx, 1024    ; Multiply by 1024 (convert KB to bytes)
    mul dx          ; Result in DX:AX
    mov [total_mem], ax
    mov [total_mem+2], dx
    mov [free_mem], ax
    mov [free_mem+2], dx
    
        mov ax, 0xE801
    int 0x15
    jc .no_extended ; Skip if not supported
    
    push ax         ; Save AX (low memory KB)
    
    ; Convert BX's 64KB blocks to bytes
    mov ax, bx
    mov dx, 64      ; Each block is 64KB
    mul dx          ; Convert to KB (result in DX:AX)
    mov bx, ax      ; Save low part
    mov cx, dx      ; Save high part
    
    pop ax          ; Restore low memory KB
    add bx, ax      ; Add low memory KB to total
    adc cx, 0       ; Handle carry
    
    ; Convert total KB to bytes
    mov ax, bx
    mov dx, cx
    push dx         ; Save high part
    mov dx, 1024    ; Multiply by 1024 (convert KB to bytes)
    mul dx          ; Low part in DX:AX
    mov bx, ax      ; Save low result
    mov cx, dx      ; Save high result
    pop ax          ; Get original high part
    mov dx, 1024    ; Multiply high part
    mul dx
    add cx, ax      ; Add to high result
    adc dx, 0       ; Handle carry
    
    ; Add extended memory to totals
    add [total_mem], bx
    adc [total_mem+2], cx
    add [free_mem], bx
    adc [free_mem+2], cx
.no_extended:
    ret

mem_alloc:
    ; Simple memory allocation (no free list management yet)
    ; Input: CX = size in bytes
    ; Output: AX = pointer to allocated block
    mov ax, [next_free]
    add [next_free], cx
    sub [free_mem], cx
    ret

mem_free:
    ; Simple stub (no actual freeing yet)
    ; Input: AX = pointer to block to free
    ret

mem_get_total:
    ; Return total memory in bytes
    mov ax, [total_mem]
    mov dx, [total_mem+2]
    ret

next_free dw 0x1000
total_mem dd 0
free_mem dd 0

mem_get_free:
    mov ax, [free_mem]
    mov dx, [free_mem+2]
    ret
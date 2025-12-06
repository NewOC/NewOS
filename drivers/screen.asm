; Screen driver - VGA text mode output
; Provides: clear_screen, print_string, print_char, scroll

; Export for Zig (cdecl wrappers)
global zig_print_char
global zig_print_string

; Wrapper for Zig (gets char from stack)
zig_print_char:
    push ebp
    mov ebp, esp
    mov al, [ebp + 8]   ; Get char from stack
    call print_char
    pop ebp
    ret

; Wrapper for Zig (gets string pointer from stack)
zig_print_string:
    push ebp
    mov ebp, esp
    push esi
    mov esi, [ebp + 8]  ; Get string ptr from stack
    call print_string
    pop esi
    pop ebp
    ret

clear_screen:
    pusha
    mov edi, VIDEO_MEMORY
    mov ecx, MAX_COLS * MAX_ROWS
    mov ax, 0x0f20
    rep stosw
    mov byte [cursor_row], 0
    mov byte [cursor_col], 0
    popa
    ret

print_string:
    pusha
.loop:
    lodsb
    test al, al
    jz .done
    call print_char
    jmp .loop
.done:
    popa
    ret

print_char:
    pusha
    
    ; 1. Проверяем Backspace (ASCII 8)
    cmp al, 8
    je .backspace
    
    ; 2. Проверяем Newline (ASCII 10)
    cmp al, 10
    je .newline
    
    ; 3. Обычный символ
    movzx ebx, byte [cursor_row]
    imul ebx, MAX_COLS
    movzx ecx, byte [cursor_col]
    add ebx, ecx
    shl ebx, 1
    add ebx, VIDEO_MEMORY
    
    mov ah, WHITE_ON_BLACK
    mov [ebx], ax
    
    inc byte [cursor_col]
    cmp byte [cursor_col], MAX_COLS
    jl .done
    
    ; Если вышли за границу строки - перенос
    jmp .newline
    
.backspace:
    ; Логика: если колонка > 0, уменьшаем её на 1
    cmp byte [cursor_col], 0
    je .done ; Если мы в начале строки, ничего не делаем (или можно подняться на строку вверх)
    
    dec byte [cursor_col]
    jmp .done

.newline:
    mov byte [cursor_col], 0
    inc byte [cursor_row]
    cmp byte [cursor_row], MAX_ROWS
    jl .done
    
    call scroll
    dec byte [cursor_row]
    
.done:
    popa
    ret

scroll:
    pusha
    mov esi, VIDEO_MEMORY + MAX_COLS * 2
    mov edi, VIDEO_MEMORY
    mov ecx, MAX_COLS * (MAX_ROWS - 1)
    rep movsw
    
    mov edi, VIDEO_MEMORY + MAX_COLS * (MAX_ROWS - 1) * 2
    mov ecx, MAX_COLS
    mov ax, 0x0f20
    rep stosw
    popa
    ret
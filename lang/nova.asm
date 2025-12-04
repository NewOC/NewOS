; Nova Programming Language Interpreter
[bits 32]

NOVA_BUFFER_SIZE equ 128

nova_buffer times NOVA_BUFFER_SIZE db 0
nova_len db 0
nova_pos db 0
last_nova_cmd times NOVA_BUFFER_SIZE db 0
last_nova_len db 0
nova_exit_flag db 0

; Variables (26 integers for a-z)
nova_vars times 26 dd 0

nova_start:
    mov byte [nova_exit_flag], 0
    mov esi, nova_welcome
    call print_string

.repl_loop:
    cmp byte [nova_exit_flag], 1
    je .exit_nova
    
    mov esi, nova_prompt
    call print_string
    
    call nova_read_command
    call nova_execute
    jmp .repl_loop

.exit_nova:
    ret

nova_read_command:
    pusha
    mov edi, nova_buffer
    mov ecx, NOVA_BUFFER_SIZE
    xor al, al
    rep stosb
    mov byte [nova_len], 0
    mov byte [nova_pos], 0
    
.read_loop:
    call wait_key
    
    cmp al, 10 ; Enter
    je .done
    
    cmp al, 8 ; Backspace
    je .backspace
    
    cmp al, KEY_UP
    je .history_up
    
    cmp al, KEY_DOWN
    je .history_down
    
    cmp al, KEY_LEFT
    je .cursor_left
    
    cmp al, KEY_RIGHT
    je .cursor_right
    
    movzx ebx, byte [nova_len]
    cmp ebx, NOVA_BUFFER_SIZE - 1
    jge .read_loop
    
    movzx ecx, byte [nova_pos]
    mov [nova_buffer + ecx], al
    inc byte [nova_len]
    inc byte [nova_pos]
    call print_char
    jmp .read_loop
    
.backspace:
    cmp byte [nova_pos], 0
    je .read_loop
    dec byte [nova_len]
    dec byte [nova_pos]
    dec byte [cursor_col]
    
    pusha
    movzx ebx, byte [cursor_row]
    imul ebx, MAX_COLS
    movzx ecx, byte [cursor_col]
    add ebx, ecx
    shl ebx, 1
    add ebx, VIDEO_MEMORY
    mov word [ebx], 0x0f20
    popa
    
    jmp .read_loop

.history_up:
    cmp byte [last_nova_len], 0
    je .read_loop
    
    call .clear_nova_line
    
    mov esi, last_nova_cmd
    mov edi, nova_buffer
    mov ecx, NOVA_BUFFER_SIZE
    rep movsb
    
    movzx eax, byte [last_nova_len]
    mov [nova_len], al
    mov [nova_pos], al
    
    mov esi, nova_buffer
    call print_string
    jmp .read_loop

.history_down:
    cmp byte [nova_len], 0
    je .read_loop
    
    call .clear_nova_line
    mov byte [nova_len], 0
    mov byte [nova_pos], 0
    jmp .read_loop

.cursor_left:
    cmp byte [nova_pos], 0
    je .read_loop
    dec byte [nova_pos]
    dec byte [cursor_col]
    jmp .read_loop

.cursor_right:
    movzx eax, byte [nova_pos]
    cmp al, [nova_len]
    jge .read_loop
    inc byte [nova_pos]
    inc byte [cursor_col]
    jmp .read_loop

.clear_nova_line:
    pusha
    mov ecx, MAX_COLS - 6
    
    movzx ebx, byte [cursor_row]
    imul ebx, MAX_COLS
    add ebx, 6
    shl ebx, 1
    add ebx, VIDEO_MEMORY
    
.clear_nova_loop:
    test ecx, ecx
    jz .clear_nova_done
    mov word [ebx], 0x0f20
    add ebx, 2
    dec ecx
    jmp .clear_nova_loop
    
.clear_nova_done:
    popa
    mov byte [cursor_col], 6
    mov byte [nova_pos], 0
    mov byte [nova_len], 0
    ret
    
.done:
    cmp byte [nova_len], 0
    je .skip_save
    
    mov esi, nova_buffer
    mov edi, last_nova_cmd
    mov ecx, NOVA_BUFFER_SIZE
    rep movsb
    movzx eax, byte [nova_len]
    mov [last_nova_len], al
    
.skip_save:
    mov al, 10
    call print_char
    popa
    ret

nova_execute:
    pusha
    
    cmp byte [nova_len], 0
    je .exec_done
    
    ; Start parsing from beginning of buffer
    mov esi, nova_buffer
    
.next_statement:
    ; Skip leading spaces
.skip_spaces:
    cmp byte [esi], ' '
    jne .check_end
    inc esi
    jmp .skip_spaces
    
.check_end:
    cmp byte [esi], 0
    je .exec_done
    
    ; Check for exit();
    push esi
    mov edi, nova_cmd_exit
    call nova_strncmp
    pop esi
    je .do_exit
    
    ; Check for print("
    push esi
    mov edi, nova_cmd_print
    call nova_strncmp
    pop esi
    je .do_print
    
    ; Unknown command - skip to next semicolon
    mov esi, nova_unknown
    call print_string
    jmp .exec_done

.do_exit:
    mov byte [nova_exit_flag], 1
    jmp .exec_done

.do_print:
    ; Skip 'print("'
    add esi, 7
    
    ; Print until closing quote
.print_loop:
    lodsb
    cmp al, '"'
    je .after_print
    test al, al
    jz .after_print
    call print_char
    jmp .print_loop

.after_print:
    mov al, 10
    call print_char
    
    ; Skip to after ");", then continue parsing
.find_semicolon:
    lodsb
    test al, al
    jz .exec_done
    cmp al, ';'
    jne .find_semicolon
    
    ; Continue with next statement
    jmp .next_statement

.exec_done:
    popa
    ret

; Nova's own strcmp (to avoid conflicts)
nova_strcmp:
    pusha
.loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc esi
    inc edi
    jmp .loop
.equal:
    popa
    xor eax, eax
    test eax, eax
    ret
.not_equal:
    popa
    xor eax, eax
    inc eax
    test eax, eax
    ret

; Nova's own strncmp
nova_strncmp:
    pusha
    mov ecx, 0
.count:
    cmp byte [edi + ecx], 0
    je .compare
    inc ecx
    jmp .count
.compare:
    mov edx, 0
.loop:
    cmp edx, ecx
    je .equal
    mov al, [esi + edx]
    mov bl, [edi + edx]
    cmp al, bl
    jne .not_equal
    inc edx
    jmp .loop
.not_equal:
    popa
    xor eax, eax
    inc eax
    test eax, eax
    ret
.equal:
    popa
    xor eax, eax
    test eax, eax
    ret

; Nova Data
nova_welcome db 'Nova Language v0.1', 10
             db 'Commands: print("text"); exit();', 10, 0
nova_prompt db 'nova> ', 0
nova_unknown db 'Syntax Error', 10, 0

nova_cmd_exit db 'exit();', 0
nova_cmd_print db 'print("', 0

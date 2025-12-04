; Shell - Command line interface
; Provides: read_command, execute_command, history management

; External Zig functions
extern zig_init
extern zig_set_cursor
extern cmd_ls
extern cmd_cat
extern cmd_touch
extern cmd_rm
extern cmd_write
extern cmd_echo
extern nova_start

read_command:
    pusha
    
    mov edi, cmd_buffer
    mov ecx, 128
    xor al, al
    rep stosb
    mov byte [cmd_len], 0
    mov byte [cmd_pos], 0
    
    ; Reset history browsing index
    movzx eax, byte [history_count]
    mov [history_index], al
    
.loop:
    call wait_key
    
    cmp al, 10
    je .done
    
    cmp al, 8
    je .backspace
    
    cmp al, KEY_UP
    je .history_up
    
    cmp al, KEY_DOWN
    je .history_down
    
    cmp al, KEY_LEFT
    je .cursor_left
    
    cmp al, KEY_RIGHT
    je .cursor_right
    
    movzx ebx, byte [cmd_len]
    cmp ebx, 127
    jge .loop
    
    movzx ecx, byte [cmd_pos]
    mov [cmd_buffer + ecx], al
    inc byte [cmd_len]
    inc byte [cmd_pos]
    call print_char
    jmp .loop
    
.backspace:
    cmp byte [cmd_pos], 0
    je .loop
    
    dec byte [cmd_len]
    dec byte [cmd_pos]
    dec byte [cursor_col]
    
    ; Clear character in buffer
    movzx ecx, byte [cmd_pos]
    mov byte [cmd_buffer + ecx], 0
    
    ; Clear on screen
    movzx ebx, byte [cursor_row]
    imul ebx, MAX_COLS
    movzx ecx, byte [cursor_col]
    add ebx, ecx
    shl ebx, 1
    add ebx, VIDEO_MEMORY
    mov word [ebx], 0x0f20
    jmp .loop

.history_up:
    cmp byte [history_count], 0
    je .loop
    
    cmp byte [history_index], 0
    je .loop
    
    dec byte [history_index]
    call .load_history
    jmp .loop

.history_down:
    movzx eax, byte [history_index]
    cmp al, [history_count]
    jge .loop
    
    inc byte [history_index]
    
    movzx eax, byte [history_index]
    cmp al, [history_count]
    jne .load_hist_down
    
    call .clear_input_line
    jmp .loop
    
.load_hist_down:
    call .load_history
    jmp .loop

.load_history:
    pusha
    
    call .clear_input_line
    
    movzx eax, byte [history_index]
    shl eax, 7
    add eax, history
    
    mov esi, eax
    mov edi, cmd_buffer
    mov ecx, 128
    rep movsb
    
    movzx ebx, byte [history_index]
    movzx eax, byte [history_lens + ebx]
    mov [cmd_len], al
    mov [cmd_pos], al
    
    mov esi, cmd_buffer
    call print_string
    
    popa
    ret

.cursor_left:
    cmp byte [cmd_pos], 0
    je .loop
    
    dec byte [cmd_pos]
    dec byte [cursor_col]
    jmp .loop

.cursor_right:
    movzx eax, byte [cmd_pos]
    cmp al, [cmd_len]
    jge .loop
    
    inc byte [cmd_pos]
    inc byte [cursor_col]
    jmp .loop

.clear_input_line:
    pusha
    mov ecx, MAX_COLS - 2
    
    movzx ebx, byte [cursor_row]
    imul ebx, MAX_COLS
    add ebx, 2
    shl ebx, 1
    add ebx, VIDEO_MEMORY
    
.clear_loop:
    test ecx, ecx
    jz .clear_ret
    mov word [ebx], 0x0f20
    add ebx, 2
    dec ecx
    jmp .clear_loop
    
.clear_ret:
    popa
    mov byte [cursor_col], 2
    mov byte [cmd_pos], 0
    mov byte [cmd_len], 0
    ret
    
.done:
    cmp byte [cmd_len], 0
    je .skip_save
    
    cmp byte [history_count], HISTORY_SIZE
    jl .add_to_history
    
    mov esi, history + 128
    mov edi, history
    mov ecx, 128 * (HISTORY_SIZE - 1)
    rep movsb
    
    mov esi, history_lens + 1
    mov edi, history_lens
    mov ecx, HISTORY_SIZE - 1
    rep movsb
    
    dec byte [history_count]
    
.add_to_history:
    movzx eax, byte [history_count]
    shl eax, 7
    add eax, history
    
    mov esi, cmd_buffer
    mov edi, eax
    mov ecx, 128
    rep movsb
    
    movzx ebx, byte [history_count]
    movzx eax, byte [cmd_len]
    mov [history_lens + ebx], al
    
    inc byte [history_count]
    
.skip_save:
    mov al, 10
    call print_char
    popa
    ret

execute_command:
    pusha
    
    cmp byte [cmd_len], 0
    je .done
    
    ; Update cursor for Zig (push in reverse: y first, then x for cdecl)
    movzx eax, byte [cursor_row]  ; y
    push eax
    movzx eax, byte [cursor_col]  ; x
    push eax
    call zig_set_cursor
    add esp, 8
    
    mov esi, cmd_buffer
    mov edi, cmd_help
    call strcmp
    je .help
    
    mov esi, cmd_buffer
    mov edi, cmd_clear
    call strcmp
    je .clear
    
    mov esi, cmd_buffer
    mov edi, cmd_about
    call strcmp
    je .about
    
    mov esi, cmd_buffer
    mov edi, cmd_nova
    call strcmp
    je .nova
    
    ; ls command
    mov esi, cmd_buffer
    mov edi, cmd_ls_str
    call strcmp
    je .do_ls
    
    ; touch <filename>
    mov esi, cmd_buffer
    mov edi, cmd_touch_str
    call strncmp
    je .do_touch
    
    ; rm <filename>
    mov esi, cmd_buffer
    mov edi, cmd_rm_str
    call strncmp
    je .do_rm
    
    ; cat <filename>
    mov esi, cmd_buffer
    mov edi, cmd_cat_str
    call strncmp
    je .do_cat
    
    ; echo text or echo text > file
    mov esi, cmd_buffer
    mov edi, cmd_echo_str
    call strncmp
    je .do_echo
    
    mov esi, unknown
    call print_string
    jmp .done
    
.help:
    mov esi, help_text
    call print_string
    jmp .done
    
.clear:
    call clear_screen
    mov esi, welcome
    call print_string
    mov esi, help_msg
    call print_string
    jmp .done
    
.about:
    mov esi, about_text
    call print_string
    jmp .done

.nova:
    call nova_start
    jmp .done

.do_ls:
    call cmd_ls
    jmp .done

.do_touch:
    ; Get filename (after "touch ")
    mov esi, cmd_buffer
    add esi, 6          ; Skip "touch "
    movzx eax, byte [cmd_len]
    sub eax, 6          ; Length of filename
    push eax            ; name_len
    push esi            ; name_ptr
    call cmd_touch
    add esp, 8
    jmp .done

.do_rm:
    ; Get filename (after "rm ")
    mov esi, cmd_buffer
    add esi, 3          ; Skip "rm "
    movzx eax, byte [cmd_len]
    sub eax, 3          ; Length of filename
    push eax            ; name_len
    push esi            ; name_ptr
    call cmd_rm
    add esp, 8
    jmp .done

.do_cat:
    ; Get filename (after "cat ")
    mov esi, cmd_buffer
    add esi, 4          ; Skip "cat "
    movzx eax, byte [cmd_len]
    sub eax, 4          ; Length of filename
    push eax            ; name_len
    push esi            ; name_ptr
    call cmd_cat
    add esp, 8
    jmp .done

.do_echo:
    ; Get text (after "echo ")
    mov esi, cmd_buffer
    add esi, 5          ; Skip "echo "
    movzx eax, byte [cmd_len]
    sub eax, 5          ; Length of text
    push eax            ; text_len (u16)
    push esi            ; text_ptr
    call cmd_echo
    add esp, 8
    jmp .done
    
.done:
    popa
    ret

; String comparison functions
strcmp:
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

strncmp:
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

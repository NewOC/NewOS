; Stable kernel with console
[org 0x1000]
[bits 32]

VIDEO_MEMORY equ 0xb8000
MAX_COLS equ 80
MAX_ROWS equ 25
WHITE_ON_BLACK equ 0x0f
GREEN_ON_BLACK equ 0x0a
HISTORY_SIZE equ 10

; Special key codes (returned by wait_key)
KEY_UP equ 0x80
KEY_DOWN equ 0x81
KEY_LEFT equ 0x82
KEY_RIGHT equ 0x83

cursor_row db 0
cursor_col db 0
shift_state db 0
extended_key db 0
cmd_buffer times 128 db 0
cmd_len db 0
cmd_pos db 0

; Command history (10 entries x 128 bytes each)
history times 1280 db 0        ; 10 * 128 bytes
history_lens times 10 db 0     ; Length of each history entry
history_count db 0             ; Number of commands in history
history_index db 0             ; Current position when browsing

start:
    call clear_screen
    
    mov esi, welcome
    call print_string
    
    mov esi, help_msg
    call print_string

main_loop:
    mov esi, prompt
    call print_string
    
    call read_command
    call execute_command
    jmp main_loop

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
    
    cmp al, 10
    je .newline
    
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

wait_key:
    push edx
    push ebx
.wait:
    mov dx, 0x64
    in al, dx
    test al, 1
    jz .wait
    
    mov dx, 0x60
    in al, dx
    
    cmp al, 0xE0
    je .extended
    
    cmp al, 0x2A
    je .shift_press
    cmp al, 0x36
    je .shift_press
    
    cmp al, 0xAA
    je .shift_release
    cmp al, 0xB6
    je .shift_release
    
    cmp byte [extended_key], 1
    je .handle_extended
    
    test al, 0x80
    jnz .wait
    
    movzx ebx, al
    cmp ebx, 128
    jge .wait
    
    cmp byte [shift_state], 1
    je .shifted
    
    mov al, [scancode + ebx]
    jmp .check_char
    
.shifted:
    mov al, [scancode_shift + ebx]
    
.check_char:
    test al, al
    jz .wait
    
    pop ebx
    pop edx
    ret

.extended:
    mov byte [extended_key], 1
    jmp .wait

.handle_extended:
    mov byte [extended_key], 0
    
    test al, 0x80
    jnz .wait
    
    cmp al, 0x48
    je .key_up
    cmp al, 0x50
    je .key_down
    cmp al, 0x4B
    je .key_left
    cmp al, 0x4D
    je .key_right
    
    jmp .wait

.key_up:
    mov al, KEY_UP
    pop ebx
    pop edx
    ret

.key_down:
    mov al, KEY_DOWN
    pop ebx
    pop edx
    ret

.key_left:
    mov al, KEY_LEFT
    pop ebx
    pop edx
    ret

.key_right:
    mov al, KEY_RIGHT
    pop ebx
    pop edx
    ret

.shift_press:
    mov byte [shift_state], 1
    jmp .wait

.shift_release:
    mov byte [shift_state], 0
    jmp .wait

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
    movzx ebx, byte [cmd_pos]
    mov byte [cmd_buffer + ebx], 0
    
    ; Clear character on screen
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
    
    ; If at the end, clear line
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
    
    ; Clear current line
    call .clear_input_line
    
    ; Calculate history entry address: history + index * 128
    movzx eax, byte [history_index]
    shl eax, 7  ; * 128
    add eax, history
    
    ; Copy to cmd_buffer
    mov esi, eax
    mov edi, cmd_buffer
    mov ecx, 128
    rep movsb
    
    ; Get length from history_lens
    movzx ebx, byte [history_index]
    movzx eax, byte [history_lens + ebx]
    mov [cmd_len], al
    mov [cmd_pos], al
    
    ; Print command (cursor_col will be updated by print_char)
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
    ; Clear the entire line from prompt position (fixed width)
    mov ecx, MAX_COLS - 2  ; Clear from after "> " to end of line
    
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
    ; Save to history if not empty
    cmp byte [cmd_len], 0
    je .skip_save
    
    ; Shift history if full
    cmp byte [history_count], HISTORY_SIZE
    jl .add_to_history
    
    ; Shift all entries up
    mov esi, history + 128
    mov edi, history
    mov ecx, 128 * (HISTORY_SIZE - 1)
    rep movsb
    
    ; Shift lengths
    mov esi, history_lens + 1
    mov edi, history_lens
    mov ecx, HISTORY_SIZE - 1
    rep movsb
    
    dec byte [history_count]
    
.add_to_history:
    ; Calculate destination: history + count * 128
    movzx eax, byte [history_count]
    shl eax, 7
    add eax, history
    
    ; Copy cmd_buffer to history
    mov esi, cmd_buffer
    mov edi, eax
    mov ecx, 128
    rep movsb
    
    ; Save length
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
    
.done:
    popa
    ret

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
    xor eax, eax      ; eax = 0
    test eax, eax     ; ZF = 1 (0 AND 0 = 0)
    ret
.not_equal:
    popa
    xor eax, eax
    inc eax           ; eax = 1
    test eax, eax     ; ZF = 0 (1 AND 1 = 1, non-zero)
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
    inc eax           ; eax = 1
    test eax, eax     ; ZF = 0
    ret
.equal:
    popa
    xor eax, eax      ; eax = 0
    test eax, eax     ; ZF = 1
    ret

welcome db '=== NewOS 32-bit Console ===', 10, 0
help_msg db 'Type "help" for commands', 10, 10, 0
prompt db '> ', 0
unknown db 'Unknown command!', 10, 0

cmd_help db 'help', 0
cmd_clear db 'clear', 0
cmd_about db 'about', 0
cmd_nova db 'nova', 0

help_text db 'Commands:', 10
          db '  help  - Show help', 10
          db '  clear - Clear screen', 10
          db '  about - About OS', 10
          db '  nova  - Start Nova Language', 10, 0

about_text db 'NewOS v0.1', 10
           db '32-bit Protected Mode OS', 10
           db 'x86 architecture', 10
           db '=== By MinecAnton209 ===', 10, 0

scancode:
    db 0,0,'1','2','3','4','5','6','7','8','9','0','-','=',8
    db 0,'q','w','e','r','t','y','u','i','o','p','[',']',10
    db 0,'a','s','d','f','g','h','j','k','l',';',"'",'`'
    db 0,'\','z','x','c','v','b','n','m',',','.','/',0
    db 0,0,' '
    times 128-($-scancode) db 0

scancode_shift:
    db 0,0,'!','@','#','$','%','^','&','*','(',')','_','+',8
    db 0,'Q','W','E','R','T','Y','U','I','O','P','{','}',10
    db 0,'A','S','D','F','G','H','J','K','L',':','"','~'
    db 0,'|','Z','X','C','V','B','N','M','<','>','?',0
    db 0,0,' '
    times 128-($-scancode_shift) db 0

%include "nova.asm"

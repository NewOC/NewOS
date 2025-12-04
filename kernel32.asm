; Stable kernel with console
[org 0x1000]
[bits 32]

VIDEO_MEMORY equ 0xb8000
MAX_COLS equ 80
MAX_ROWS equ 25
WHITE_ON_BLACK equ 0x0f
GREEN_ON_BLACK equ 0x0a

cursor_row db 0
cursor_col db 0
cmd_buffer times 128 db 0
cmd_len db 0

start:
    ; Clear screen
    call clear_screen
    
    ; Print welcome message
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
    
    ; Calculate position
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
.wait:
    mov dx, 0x64
    in al, dx
    test al, 1
    jz .wait
    
    mov dx, 0x60
    in al, dx
    
    test al, 0x80
    jnz .wait
    
    movzx ebx, al
    cmp ebx, 58
    jge .wait
    
    mov al, [scancode + ebx]
    test al, al
    jz .wait
    
    pop edx
    ret

read_command:
    pusha
    
    mov edi, cmd_buffer
    mov ecx, 128
    xor al, al
    rep stosb
    mov byte [cmd_len], 0
    
.loop:
    call wait_key
    
    cmp al, 10
    je .done
    
    cmp al, 8
    je .backspace
    
    movzx ebx, byte [cmd_len]
    cmp ebx, 127
    jge .loop
    
    mov [cmd_buffer + ebx], al
    inc byte [cmd_len]
    call print_char
    jmp .loop
    
.backspace:
    cmp byte [cmd_len], 0
    je .loop
    
    dec byte [cmd_len]
    dec byte [cursor_col]
    
    movzx ebx, byte [cursor_row]
    imul ebx, MAX_COLS
    movzx ecx, byte [cursor_col]
    add ebx, ecx
    shl ebx, 1
    add ebx, VIDEO_MEMORY
    mov word [ebx], 0x0f20
    jmp .loop
    
.done:
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
    cmp eax, eax
    ret
.not_equal:
    popa
    cmp eax, ebx
    ret

welcome db '=== NewOS 32-bit Console ===', 10, 0
help_msg db 'Type "help" for commands', 10, 10, 0
prompt db '> ', 0
unknown db 'Unknown command!', 10, 0

cmd_help db 'help', 0
cmd_clear db 'clear', 0
cmd_about db 'about', 0

help_text db 'Commands:', 10
          db '  help  - Show help', 10
          db '  clear - Clear screen', 10
          db '  about - About OS', 10, 0

about_text db 'NewOS v0.1', 10
           db '32-bit Protected Mode OS', 10
           db 'x86 architecture', 10
           db '=== By MinecAnton209 ===', 10, 0

scancode:
    db 0,0,'1','2','3','4','5','6','7','8','9','0','-','=',8
    db 0,'q','w','e','r','t','y','u','i','o','p','[',']',10
    db 0,'a','s','d','f','g','h','j','k','l',';',"'",'`'
    db 0,'\','z','x','c','v','b','n','m',',','.','/',0
    db 0,0,0,' '

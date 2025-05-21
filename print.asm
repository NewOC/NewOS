; Print null-terminated string
; Input: SI = string pointer
print_string:
    pusha
    mov ah, 0x0E    ; BIOS teletype function

.char_loop:
    lodsb           ; Load next character
    or al, al       ; Check for null terminator
    jz .done
    int 0x10
    jmp .char_loop

.done:
    popa
    ret

; Print hexadecimal word
; Input: AX = value to print
print_hex_word:
    pusha
    mov cx, 4
    mov bx, ax

.digit_loop:
    rol bx, 4
    mov ax, bx
    and ax, 0x000F
    cmp al, 9
    jbe .digit_09
    add al, 7
.digit_09:
    add al, '0'
    mov ah, 0x0E
    int 0x10
    loop .digit_loop

    popa
    ret
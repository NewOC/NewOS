; Keyboard driver - PS/2 keyboard input
; Provides: wait_key, scancode tables

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

; Scancode tables
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

; Keyboard driver - PS/2 keyboard input
; Provides: wait_key (block until key press)

; External key codes
KEY_UP    equ 0x80
KEY_DOWN  equ 0x81
KEY_LEFT  equ 0x82
KEY_RIGHT equ 0x83

global wait_key

; Wait for a key press and return ASCII/Code in AL
wait_key:
    push edx
    push ebx
    
.wait:
    ; Check PS/2 status register (0x64)
    mov dx, 0x64
    in al, dx
    test al, 1          ; Output buffer full?
    jz .wait
    
    ; Read the scancode from port 0x60
    mov dx, 0x60
    in al, dx
    
    ; Handle Extended Key prefix (0xE0)
    cmp al, 0xE0
    je .extended
    
    ; Handle Shift press (Left: 0x2A, Right: 0x36)
    cmp al, 0x2A
    je .shift_press
    cmp al, 0x36
    je .shift_press
    
    ; Handle Shift release (Left: 0xAA, Right: 0xB6)
    cmp al, 0x2A + 0x80
    je .shift_release
    cmp al, 0x36 + 0x80
    je .shift_release
    
    ; Handle extended keys (Arrows)
    cmp byte [extended_key], 1
    je .handle_extended
    
    ; Skip release codes (break codes) for normal keys
    test al, 0x80
    jnz .wait
    
    movzx ebx, al
    cmp ebx, 128
    jge .wait
    
    ; Translate scancode to ASCII
    cmp byte [shift_state], 1
    je .shifted
    
    mov al, [scancode + ebx]
    jmp .check_char
    
.shifted:
    mov al, [scancode_shift + ebx]
    
.check_char:
    test al, al         ; Ignore zero entries (unmapped keys)
    jz .wait
    
    pop ebx
    pop edx
    ret

; --- Special Key Handlers ---

.extended:
    mov byte [extended_key], 1
    jmp .wait

.handle_extended:
    mov byte [extended_key], 0
    
    test al, 0x80       ; Skip release codes
    jnz .wait
    
    ; Map arrow scancodes
    cmp al, 0x48        ; UP
    je .key_up
    cmp al, 0x50        ; DOWN
    je .key_down
    cmp al, 0x4B        ; LEFT
    je .key_left
    cmp al, 0x4D        ; RIGHT
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

; --- Scancode Translation Tables ---

; Normal keys
scancode:
    db 0,0,'1','2','3','4','5','6','7','8','9','0','-','=',8
    db 0,'q','w','e','r','t','y','u','i','o','p','[',']',10
    db 0,'a','s','d','f','g','h','j','k','l',';',"'",'`'
    db 0,'\','z','x','c','v','b','n','m',',','.','/',0
    db 0,0,' '
    times 128-($-scancode) db 0

; Shifted keys
scancode_shift:
    db 0,0,'!','@','#','$','%','^','&','*','(',')','_','+',8
    db 0,'Q','W','E','R','T','Y','U','I','O','P','{','}',10
    db 0,'A','S','D','F','G','H','J','K','L',':','"','~'
    db 0,'|','Z','X','C','V','B','N','M','<','>','?',0
    db 0,0,' '
    times 128-($-scancode_shift) db 0

; Disk operations for bootloader
disk_load:
    pusha
    push dx

    mov ah, 0x02    ; BIOS read sector function
    mov al, dh      ; Number of sectors to read
    mov ch, 0x00    ; Cylinder 0
    mov dh, 0x00    ; Head 0
    mov cl, 0x02    ; Sector 2 (1-based)
    mov dl, 0x00    ; Drive number (0x00 for floppy disk)

    int 0x13        ; BIOS interrupt
    jc disk_error   ; Jump if error

    pop dx
    cmp al, dh      ; Check if all sectors read
    jne disk_error
    popa
    ret

disk_error:
    mov si, disk_error_msg
    call print_string
    jmp $

disk_error_msg db 'Disk read error!', 0
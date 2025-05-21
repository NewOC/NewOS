; File system operations

; Initialize file system
fs_init:
    ret

; Create file
; Input: DS:SI = filename
fs_create:
    ret

; Delete file
; Input: DS:SI = filename
fs_delete:
    ret

; Read file
; Input: DS:SI = filename, ES:DI = buffer, CX = bytes to read
; Output: AX = bytes read
fs_read:
    ret

; Write file
; Input: DS:SI = filename, ES:DI = buffer, CX = bytes to write
; Output: AX = bytes written
fs_write:
    ret

; List directory
; Input: ES:DI = buffer
; Output: AX = number of files
fs_list:
    ret
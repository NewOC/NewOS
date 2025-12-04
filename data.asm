; Data strings and messages

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

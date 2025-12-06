; Data strings and messages

welcome db '=== NewOS 32-bit Console ===', 10, 0
help_msg db 'Type "help" for commands', 10, 10, 0
prompt db '> ', 0
unknown db 'Unknown command!', 10, 0

cmd_help db 'help', 0
cmd_clear db 'clear', 0
cmd_about db 'about', 0
cmd_nova db 'nova', 0
cmd_ls_str db 'ls', 0
cmd_touch_str db 'touch ', 0
cmd_rm_str db 'rm ', 0
cmd_cat_str db 'cat ', 0
cmd_echo_str db 'echo ', 0
cmd_reboot_str db 'reboot', 0
cmd_shutdown_str db 'shutdown', 0

help_text db 'Commands:', 10
          db '  help           - Show help', 10
          db '  clear          - Clear screen', 10
          db '  about          - About OS', 10
          db '  nova           - Start Nova', 10
          db '  reboot         - Reboot PC', 10
          db '  shutdown       - Shutdown PC', 10
          db '  ls             - List files', 10
          db '  touch <file>   - Create file', 10
          db '  rm <file>      - Delete file', 10
          db '  cat <file>     - Show contents', 10
          db '  echo <text>    - Print text', 10, 0

about_text db 'NewOS v0.3', 10
           db '32-bit Protected Mode OS', 10
           db 'x86 + Zig kernel modules', 10
           db '=== By MinecAnton209 ===', 10, 0

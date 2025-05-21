@echo off

:: Check for required tools
where nasm >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: NASM is not installed or not in PATH
    echo Download from https://www.nasm.us/
    exit /b 1
)

:: Assemble bootloader
nasm -f bin bootloader.asm -o bootloader.bin
if not exist bootloader.bin (
    echo Error: Failed to assemble bootloader
    exit /b 1
)

:: Assemble kernel
nasm -f bin kernel.asm -o kernel.bin
if not exist kernel.bin (
    echo Error: Failed to assemble kernel
    exit /b 1
)

:: Create disk image (Windows alternative to dd)
fsutil file createnew os.img 1474560 >nul

:: Write bootloader to first sector
copy /b bootloader.bin /y os.img >nul

:: Write kernel to second sector
copy /b os.img + kernel.bin /y os.img >nul

:: Clean up temporary files
del bootloader.bin kernel.bin bootloader.hex kernel.hex

echo Build complete! Run with: qemu-system-i386 -fda os.img
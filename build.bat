@echo off
echo Building NewOS...

if not exist build mkdir build

echo Assembling bootloader...
nasm -f bin bootloader.asm -o build\bootloader.bin
if errorlevel 1 (
    echo Error assembling bootloader!
    pause
    exit /b 1
)

echo Assembling kernel...
nasm -f bin kernel32.asm -o build\kernel32.bin
if errorlevel 1 (
    echo Error assembling kernel!
    pause
    exit /b 1
)

echo Creating image...
copy /b build\bootloader.bin + build\kernel32.bin build\os-image.bin

echo.
echo Build successful!
dir build\bootloader.bin | findstr bootloader
dir build\kernel32.bin | findstr kernel32
dir build\os-image.bin | findstr os-image
echo.
echo Run: qemu-system-i386 -fda build\os-image.bin
pause
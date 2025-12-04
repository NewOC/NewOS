@echo off
echo Building NewOS...

:: Create build directory
if not exist build mkdir build

:: Assemble bootloader
echo Assembling bootloader...
nasm -f bin bootloader.asm -o build\bootloader.bin
if %errorlevel% neq 0 (
    echo Error assembling bootloader!
    pause
    exit /b 1
)

:: Assemble kernel to ELF object file
echo Assembling kernel...
nasm -f elf32 kernel32.asm -o build\kernel32.o
if %errorlevel% neq 0 (
    echo Error assembling kernel!
    pause
    exit /b 1
)

:: Build Zig modules
echo Building Zig modules...
pushd zig
zig build
if %errorlevel% neq 0 (
    echo Error building Zig modules!
    popd
    pause
    exit /b 1
)
popd

:: Link kernel with Zig modules (strip during link)
echo Linking...
zig ld.lld -m elf_i386 -T linker.ld --strip-all -o build\kernel32.elf build\kernel32.o zig\build\shell_cmds.o
if %errorlevel% neq 0 (
    echo Error linking!
    pause
    exit /b 1
)

:: Extract flat binary from ELF
echo Extracting binary...
zig objcopy -O binary build\kernel32.elf build\kernel32.bin
if %errorlevel% neq 0 (
    echo Error extracting binary!
    pause
    exit /b 1
)

:: Create final image
echo Creating image...
cmd /c "copy /b build\bootloader.bin + build\kernel32.bin build\os-image.bin"
if %errorlevel% neq 0 (
    echo Error creating image!
    pause
    exit /b 1
)

echo.
echo Build successful!
dir build\*.bin

echo.
echo Run: qemu-system-i386 -fda build\os-image.bin
pause
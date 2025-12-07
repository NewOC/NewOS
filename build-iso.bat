@echo off

:: Ensure base image exists
if not exist NewOS.img (
    echo NewOS.img not found. Running build-img.bat...
    call build-img.bat
    if errorlevel 1 exit /b 1
)

:: Build Tool
echo Building ISO Tool...
if not exist tools\mkiso.exe (
    zig build-exe tools/mkiso.zig -femit-bin=tools/mkiso.exe
    if %errorlevel% neq 0 (
        echo Error building mkiso tool!
        pause
        exit /b 1
    )
)

:: Run Tool
echo Creating NewOS.iso...
tools\mkiso.exe NewOS.img NewOS.iso
if %errorlevel% neq 0 (
    echo Error creating ISO!
    pause
    exit /b 1
)

echo Success! Created NewOS.iso

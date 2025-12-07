@echo off
if not exist build\os-image.bin (
    echo Error: build\os-image.bin not found!
    echo Please run 'build.bat' first.
    pause
    exit /b 1
)

echo Creating NewOS.img...
copy build\os-image.bin NewOS.img >nul
if %errorlevel% neq 0 (
    echo Error creating NewOS.img!
    pause
    exit /b 1
)

echo Success! Created NewOS.img

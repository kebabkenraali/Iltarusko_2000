@echo off
echo ============================================
echo  Iltarusko_2000 - Twilight: 2000 Remake
echo ============================================
echo.

set "GODOT=%~dp0engine\godot.exe"
if not exist "%GODOT%" (
  where godot >nul 2>nul
  if errorlevel 1 (
    echo Godotia ei loytynyt. Aja install.ps1 lataamaan moottori,
    echo tai asenna Godot 4.7.2+ ja lisase godot.exe PATHiin.
    pause
    exit /b 1
  )
  set "GODOT=godot"
)

"%GODOT%" --path "%~dp0godot" %*

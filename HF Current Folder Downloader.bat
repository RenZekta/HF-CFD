@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

:: Get the current directory path where the bat file is located
set "CURRENT_DIR=%~dp0"
if "%CURRENT_DIR:~-1%"=="\" set "CURRENT_DIR=%CURRENT_DIR:~0,-1%"

echo ===================================================
echo   Hugging Face Current Folder Downloader
echo ===================================================
echo Files will be downloaded to: %CURRENT_DIR%
echo.

:input_loop
set "USER_INPUT="
set /p "USER_INPUT=Paste the CLI command from the website: "

:: Check for empty input
if "%USER_INPUT%"=="" (
    echo [Error] Input cannot be empty.
    goto input_loop
)

:: Validate format: command must contain "hf download"
echo !USER_INPUT! | findstr /i /c:"hf download" >nul
if errorlevel 1 (
    echo [Error] Invalid command format. 
    echo The command must start with "hf download ..."
    echo.
    goto input_loop
)

echo.
echo Format is valid. Starting download...
echo ---------------------------------------------------

:: Execute the user command with the local directory flag appended
!USER_INPUT! --local-dir "%CURRENT_DIR%"

echo ---------------------------------------------------
echo Done! Press any key to exit...
pause > nul

@echo off
:: ===================================================
:: CFD - Current Folder Downloader
:: Callable from any folder. Downloads into the folder
:: cmd is currently opened in. Since "hf download" can
:: only use one .cache folder at a time, extra commands
:: pasted while a download is running are queued and
:: run one after another by a background worker window.
::
:: Usage:
::   cfd hf download hf download hf://prism-ml/Bonsai-27B-gguf/Bonsai-27B-Q1_0.gguf
::   cfd https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf?download=true
::       (plain "download" button link, pasted as-is - a trailing
::        "?download=true" is stripped automatically and the link is
::        turned into a "curl -L -C - -O" command)
::   cfd status       - show active/current/queued downloads here
::   cfd continue / c  - resume after a crash/interruption using saved queue data
::   cfd clear         - wipe the pending queue (and in-progress marker) here
::   cfd uninstall     - remove cfd from PATH and delete its files
:: ===================================================

setlocal enabledelayedexpansion

:: Literal double-quote character, used later to wrap a pasted URL in
:: quotes when building a curl command. Must be defined here at the top
:: level (not inside a parenthesized block) to avoid batch parsing issues.
set QM=^"

if /i "%~1"=="uninstall" ( call :uninstall & exit /b 0 )
if /i "%~1"=="status"    ( call :status    & exit /b 0 )
if /i "%~1"=="queue"     ( call :status    & exit /b 0 )
if /i "%~1"=="clear"     ( call :clearqueue & exit /b 0 )
if /i "%~1"=="continue"  ( call :forcecontinue & exit /b 0 )
if /i "%~1"=="c"         ( call :forcecontinue & exit /b 0 )
if /i "%~1"=="__worker__" ( call :worker_loop "%~2" & exit /b 0 )

set "TARGET_DIR=%CD%"
set "USER_INPUT=%*"

if "%USER_INPUT%"=="" (
    echo ===================================================
    echo CFD - Current Folder Downloader
    echo ===================================================
    echo Usage:
    echo   cfd hf download ^<hf://repo/path or model id^>
    echo   cfd ^<direct download URL, e.g. the "download" button link^>
    echo   cfd status          - show active/current/queued downloads here
    echo   cfd continue / c    - resume after a crash/interruption
    echo   cfd clear           - wipe the pending queue here
    echo   cfd uninstall       - remove cfd
    echo.
    echo Examples:
    echo   cfd hf download hf://prism-ml/Bonsai-27B-gguf/Bonsai-27B-Q1_0.gguf
    echo   cfd https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf?download=true
    endlocal
    exit /b 1
)

:: Detect which of the two supported formats we were given:
::   IS_HF  = 1 -> a "hf download ..." command, used as-is
::   IS_URL = 1 -> a plain direct-download URL/link, converted to a curl command
set "IS_HF=0"
echo !USER_INPUT! | findstr /i /c:"hf download" >nul
if not errorlevel 1 set "IS_HF=1"

set "IS_URL=0"
if /i "!USER_INPUT:~0,7!"=="http://"  set "IS_URL=1"
if /i "!USER_INPUT:~0,8!"=="https://" set "IS_URL=1"

if "!IS_HF!"=="0" if "!IS_URL!"=="0" (
    echo [Error] Invalid command format.
    echo Paste either an "hf download ..." command, or a direct download
    echo URL ^(e.g. the "download" button link from a huggingface.co file page^).
    endlocal
    exit /b 1
)

if "!IS_HF!"=="0" if "!IS_URL!"=="1" (
    :: Plain download-button URL, e.g. ...file.gguf?download=true
    set "URL=!USER_INPUT!"
    :: Strip the trailing query string. A plain "download" button
    :: link ends in ?download=true, but batch substitution cannot
    :: use that literal as a pattern - the first "=" ends the
    :: pattern and the rest becomes the replacement. Truncate at
    :: the first "?" instead: everything after it is the query
    :: string.
    for /f "delims=?" %%A in ("!URL!") do set "URL=%%A"
    set "USER_INPUT=curl -L -C - -O !QM!!URL!!QM!"
    echo [CFD] Parsed as direct URL - will run: !USER_INPUT!
)

set "LOCK_FILE=%TARGET_DIR%\.cfd.lock"
set "QUEUE_FILE=%TARGET_DIR%\.cfd.queue"

:: Append this command as a new line in the folder's queue file
echo !USER_INPUT!>>"%QUEUE_FILE%"

:: Work out its position in the queue for feedback
set /a POS=0
for /f "usebackq delims=" %%L in ("%QUEUE_FILE%") do set /a POS+=1

if exist "%LOCK_FILE%" (
    echo [CFD] A download is already running in this folder.
    echo [CFD] Added to queue at position !POS!: !USER_INPUT!
    echo [CFD] It will start automatically once earlier downloads finish.
) else (
    echo [CFD] Queued ^(position !POS!^): !USER_INPUT!
    echo [CFD] Opening download worker window...
    start "CFD Worker" cmd /c ""%~f0" __worker__ "%TARGET_DIR%""
)

endlocal
exit /b 0

:: ===================================================
:: Worker: runs in its own window, processes the queue
:: for one folder until empty, then closes itself.
:: While a command is running, it is mirrored into
:: .cfd.current so a crash can be recovered with
:: "cfd continue".
:: ===================================================
:worker_loop
setlocal enabledelayedexpansion
set "WDIR=%~1"
cd /d "%WDIR%"
set "LOCK_FILE=%WDIR%\.cfd.lock"
set "QUEUE_FILE=%WDIR%\.cfd.queue"
set "CURRENT_FILE=%WDIR%\.cfd.current"

echo cfd worker running> "%LOCK_FILE%"

echo ===================================================
echo CFD Worker
echo Folder: %WDIR%
echo ===================================================

:worker_next
if not exist "%QUEUE_FILE%" goto worker_done

set "NEXT_CMD="
for /f "usebackq delims=" %%L in ("%QUEUE_FILE%") do (
    if not defined NEXT_CMD set "NEXT_CMD=%%L"
)
if not defined NEXT_CMD goto worker_done

:: Remove the line we just picked up, keep the rest of the queue
more +1 "%QUEUE_FILE%" > "%QUEUE_FILE%.tmp" 2>nul
del /f /q "%QUEUE_FILE%" >nul 2>&1
set "TMPSIZE=0"
for %%A in ("%QUEUE_FILE%.tmp") do set "TMPSIZE=%%~zA"
if !TMPSIZE! gtr 0 (
    move /y "%QUEUE_FILE%.tmp" "%QUEUE_FILE%" >nul
) else (
    del /f /q "%QUEUE_FILE%.tmp" >nul 2>&1
)

:: Mark this one as "currently downloading" in case of a crash
echo !NEXT_CMD!> "%CURRENT_FILE%"

echo ---------------------------------------------------
echo [CFD] Downloading: !NEXT_CMD!
echo ---------------------------------------------------

echo !NEXT_CMD! | findstr /i /c:"hf download" >nul
if not errorlevel 1 (
    !NEXT_CMD! --local-dir "%WDIR%"
) else (
    :: Direct-URL downloads (curl) already run in the target folder,
    :: since the worker cd's into it above.
    !NEXT_CMD!
)

if !errorlevel! equ 0 (
    if exist "%WDIR%\.cache" (
        echo Cleaning up .cache folder...
        rd /s /q "%WDIR%\.cache"
    )
    del /f /q "%CURRENT_FILE%" >nul 2>&1
    echo [CFD] Finished: !NEXT_CMD!
) else (
    echo.
    echo [CFD] [Warning] Download failed or was interrupted. Keeping .cache folder.
    echo [CFD] Moving on to the next queued item, if any...
    del /f /q "%CURRENT_FILE%" >nul 2>&1
)

goto worker_next

:worker_done
del /f /q "%LOCK_FILE%" >nul 2>&1
echo ===================================================
echo [CFD] Queue empty - all downloads for this folder are complete.
echo This window will close automatically in 5 seconds.
echo ===================================================
timeout /t 5 >nul
endlocal
exit /b 0

:: ===================================================
:: Helper commands
:: ===================================================
:status
setlocal enabledelayedexpansion
set "WDIR=%CD%"
set "LOCK_FILE=%WDIR%\.cfd.lock"
set "QUEUE_FILE=%WDIR%\.cfd.queue"
set "CURRENT_FILE=%WDIR%\.cfd.current"

if exist "%LOCK_FILE%" (
    echo [CFD] A download worker is active in this folder.
) else (
    echo [CFD] No active worker in this folder.
)

if exist "%CURRENT_FILE%" (
    for /f "usebackq delims=" %%L in ("%CURRENT_FILE%") do echo [CFD] In progress: %%L
)

if exist "%QUEUE_FILE%" (
    echo [CFD] Pending items in queue:
    set /a I=0
    for /f "usebackq delims=" %%L in ("%QUEUE_FILE%") do (
        set /a I+=1
        echo   !I!. %%L
    )
) else (
    echo [CFD] Queue is empty.
)
endlocal
exit /b 0

:clearqueue
setlocal enabledelayedexpansion
set "QUEUE_FILE=%CD%\.cfd.queue"
set "CURRENT_FILE=%CD%\.cfd.current"
set "FOUND=0"
if exist "%QUEUE_FILE%" (
    del /f /q "%QUEUE_FILE%" >nul 2>&1
    set "FOUND=1"
)
if exist "%CURRENT_FILE%" (
    del /f /q "%CURRENT_FILE%" >nul 2>&1
    set "FOUND=1"
)
if "!FOUND!"=="1" (
    echo [CFD] Pending queue and in-progress marker cleared for this folder.
    echo [CFD] Note: any partially downloaded .cache folder is left untouched.
) else (
    echo [CFD] Queue was already empty.
)
endlocal
exit /b 0

:forcecontinue
setlocal enabledelayedexpansion
set "WDIR=%CD%"
set "LOCK_FILE=%WDIR%\.cfd.lock"
set "QUEUE_FILE=%WDIR%\.cfd.queue"
set "CURRENT_FILE=%WDIR%\.cfd.current"

:: Clear any stale lock - a worker can't be genuinely running and reachable
:: from this same folder at the same time, so it's always safe to clear it
:: before resuming.
if exist "%LOCK_FILE%" del /f /q "%LOCK_FILE%" >nul 2>&1

set "CURRENT_CMD="
if exist "%CURRENT_FILE%" (
    for /f "usebackq delims=" %%L in ("%CURRENT_FILE%") do (
        if not defined CURRENT_CMD set "CURRENT_CMD=%%L"
    )
)

if not defined CURRENT_CMD if not exist "%QUEUE_FILE%" (
    echo [CFD] Nothing to continue - no saved queue or in-progress download found here.
    endlocal
    exit /b 0
)

:: Put the interrupted download back at the front of the queue, ahead of
:: anything else that was still waiting
set "TMPFILE=%QUEUE_FILE%.tmp"
> "%TMPFILE%" (
    if defined CURRENT_CMD echo !CURRENT_CMD!
    if exist "%QUEUE_FILE%" type "%QUEUE_FILE%"
)
if exist "%QUEUE_FILE%" del /f /q "%QUEUE_FILE%" >nul 2>&1
move /y "%TMPFILE%" "%QUEUE_FILE%" >nul
if exist "%CURRENT_FILE%" del /f /q "%CURRENT_FILE%" >nul 2>&1

if defined CURRENT_CMD (
    echo [CFD] Resuming interrupted download ^(existing .cache will be reused/verified^): !CURRENT_CMD!
) else (
    echo [CFD] Resuming queued downloads for this folder...
)
start "CFD Worker" cmd /c ""%~f0" __worker__ "%WDIR%""

endlocal
exit /b 0

:uninstall
setlocal enabledelayedexpansion
set "INSTALL_DIR=%~dp0"
if "%INSTALL_DIR:~-1%"=="\" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"

echo ===================================================
echo CFD - Uninstalling
echo ===================================================
echo Install folder: %INSTALL_DIR%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$installDir = '%INSTALL_DIR%';" ^
 "$userPath = [Environment]::GetEnvironmentVariable('Path','User');" ^
 "$parts = $userPath -split ';' | Where-Object { $_ -ne '' -and $_ -ne $installDir };" ^
 "$newPath = $parts -join ';';" ^
 "[Environment]::SetEnvironmentVariable('Path', $newPath, 'User');" ^
 "Write-Host 'Removed' $installDir 'from PATH.'"

echo Removing installed files...
:: Spawn a detached process to delete the folder after this script exits,
:: since the running .bat file lives inside it.
start "" cmd /c "timeout /t 1 /nobreak >nul & rmdir /s /q "%INSTALL_DIR%""

echo.
echo Done. cfd has been uninstalled.
echo Close and reopen any terminal windows for the change to take effect.
endlocal
exit /b 0

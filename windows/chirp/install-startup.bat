@echo off
:: Add/remove Chirp from Windows startup using Startup folder shortcut
:: Run as: install-startup.bat         (to install)
::         install-startup.bat remove  (to remove)

set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "SHORTCUT=%STARTUP%\Chirp Dictation.bat"

if /I "%1"=="remove" goto :remove

echo Installing Chirp to start at login...
echo @echo off > "%SHORTCUT%"
echo cd /d "%~dp0" >> "%SHORTCUT%"
echo call start-chirp.bat >> "%SHORTCUT%"
echo Done! Chirp will now start automatically when you log in.
echo Shortcut: %SHORTCUT%
echo.
echo To remove: install-startup.bat remove
exit /b

:remove
echo Removing Chirp from startup...
if exist "%SHORTCUT%" (
    del "%SHORTCUT%"
    echo Done! Chirp will no longer start at login.
) else (
    echo Startup entry not found or already removed.
)

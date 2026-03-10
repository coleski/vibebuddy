@echo off
:: Start Chirp dictation in the background (no visible terminal)
cd /d "%~dp0"

:: Use pythonw via uv to avoid a console window
start "" /B cmd /c "uv run chirp 2>>chirp-error.log" >NUL 2>&1
echo Chirp started.

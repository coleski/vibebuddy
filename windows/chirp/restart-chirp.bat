@echo off
:: Restart Chirp dictation
cd /d "%~dp0"
call stop-chirp.bat
timeout /t 2 /nobreak >NUL
call start-chirp.bat

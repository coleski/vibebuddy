@echo off
:: Stop Chirp dictation
taskkill /FI "WINDOWTITLE eq chirp-dictation" /T /F >NUL 2>&1
if not errorlevel 1 (
    echo Chirp stopped.
) else (
    echo Chirp was not running.
)

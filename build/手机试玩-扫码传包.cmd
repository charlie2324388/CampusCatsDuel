@echo off
chcp 65001 >nul
setlocal
set "PYTHONUTF8=1"
set "BUNDLED_PY=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if exist "%BUNDLED_PY%" (
  "%BUNDLED_PY%" "%~dp0..\dev\手机试玩传包.py" %*
) else (
  py -3 "%~dp0..\dev\手机试玩传包.py" %*
)
set "TRANSFER_RESULT=%ERRORLEVEL%"
if not "%TRANSFER_RESULT%"=="0" if "%~1"=="" pause
exit /b %TRANSFER_RESULT%

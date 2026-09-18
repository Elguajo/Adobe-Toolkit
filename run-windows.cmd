@echo off
setlocal

set ACTION=%~1
set DEST=%~2

if /I "%ACTION%"=="backup" goto do_backup
if /I "%ACTION%"=="restore" goto do_restore
if /I "%ACTION%"=="clean" goto do_clean_kill
if /I "%ACTION%"=="clean-preview" goto do_clean_preview
if /I "%ACTION%"=="clean-full" goto do_clean_full

if not "%ACTION%"=="" (
  echo Usage: %~nx0 [backup^|restore path^|clean^|clean-preview^|clean-full]
  goto end
)

echo Adobe Environment Toolkit
echo.
echo 1^) Backup settings
echo 2^) Restore settings
echo 3^) Stop Adobe processes and services
echo 4^) Preview full cleanup
echo 5^) Full cleanup
echo.
set /p CHOICE=Select (1-5):

if "%CHOICE%"=="1" goto do_backup
if "%CHOICE%"=="2" goto do_restore_prompt
if "%CHOICE%"=="3" goto do_clean_kill
if "%CHOICE%"=="4" goto do_clean_preview
if "%CHOICE%"=="5" goto do_clean_full

echo Invalid choice.
goto end

:do_backup
call "%~dp0windows\run-backup.cmd"
goto end

:do_restore_prompt
set /p DEST=Enter full path to backup folder: 
:do_restore
if "%DEST%"=="" (
  echo Please specify backup folder path for restore.
  goto end
)
call "%~dp0windows\run-restore.cmd" "%DEST%"
goto end

:do_clean_kill
call "%~dp0windows\clean\run-kill.cmd"
goto end

:do_clean_preview
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\clean\AdobeCleaner.ps1" -Mode DryRunFull
goto end

:do_clean_full
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\clean\AdobeCleaner.ps1" -Mode Full

:end
endlocal

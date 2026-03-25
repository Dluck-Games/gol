@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0run-tests.ps1"
if errorlevel 1 pause

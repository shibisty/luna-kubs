@echo off
rem Starts Luna on minikube: see luna.ps1 (it asks for an administrator).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0luna.ps1" start %*

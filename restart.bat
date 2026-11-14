@echo off
rem Restarts Luna on minikube: see luna.ps1 (it asks for an administrator).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0luna.ps1" restart %*

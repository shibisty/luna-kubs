@echo off
rem Tag the images docker compose built and push them to your DigitalOcean
rem Container Registry, all into one repository (<registry>/luna, tags
rem <service>-<tag>: the Basic plan allows five repositories, Luna has seven
rem images):
rem                       k8s\do\push.bat <registry> <tag> [service...]
rem e.g.                  k8s\do\push.bat lunaregistry 0.1.0
rem               or     k8s\do\push.bat registry.digitalocean.com/lunaregistry 0.1.0
rem only some images:     k8s\do\push.bat lunaregistry 0.1.1 nginx
rem   (dashboard auth pages files nginx mail postgres; postgres is always tag 18)
rem First: doctl registry login   (and docker compose build), in a window
rem without minikube's docker-env.
rem Then set the same registry and versions in k8s\do\kustomization.yaml.
setlocal
if "%~2"=="" (
  echo usage: push.bat ^<registry^> ^<tag^> [service...]
  exit /b 2
)
rem The registry's name, with or without registry.digitalocean.com/ in front.
set N=%~1
set N=%N:registry.digitalocean.com/=%
set R=registry.digitalocean.com/%N%/luna
set T=%~2
shift
shift
if not "%~1"=="" goto args
for %%s in (dashboard auth pages files nginx mail postgres) do call :push %%s || exit /b 1
goto done
:args
if "%~1"=="" goto done
call :push %~1 || exit /b 1
shift
goto args
:done
echo Pushed %T% to %R%.
exit /b 0

:push
if "%1"=="mail" (
  set SRC=luna-mail:latest
  set DST=%R%:mail-%T%
) else if "%1"=="postgres" (
  set SRC=luna-postgres:18
  set DST=%R%:postgres-18
) else (
  set SRC=luna-%1:local
  set DST=%R%:%1-%T%
)
docker tag %SRC% %DST% || exit /b 1
docker push %DST% || exit /b 1
exit /b 0

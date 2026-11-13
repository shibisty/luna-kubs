@echo off
rem Tag the images docker compose built and push them to your DigitalOcean
rem Container Registry:   k8s\do\push.bat <registry> <tag>
rem e.g.                  k8s\do\push.bat luna-registry 0.1.0
rem First: doctl registry login   (and docker compose build).
rem Then set the same registry and tag in k8s\do\kustomization.yaml.
setlocal
if "%~2"=="" (
  echo usage: push.bat ^<registry^> ^<tag^>
  exit /b 2
)
set R=registry.digitalocean.com/%~1
set T=%~2
for %%s in (luna-dashboard luna-auth luna-pages luna-files luna-nginx) do (
  docker tag %%s:local %R%/%%s:%T% || exit /b 1
  docker push %R%/%%s:%T% || exit /b 1
)
docker tag luna-mail:latest %R%/luna-mail:%T% || exit /b 1
docker push %R%/luna-mail:%T% || exit /b 1
docker tag luna-postgres:18 %R%/luna-postgres:18 || exit /b 1
docker push %R%/luna-postgres:18 || exit /b 1
echo Pushed %T% to %R%.

<#
luna.ps1 - Luna on minikube (Windows, the Hyper-V driver).

  .\luna.ps1 start            minikube, the images (first time), secrets (first time), the
                              manifests, the hosts file; waits until every service is up
  .\luna.ps1 stop             stops minikube (the data stays)
  .\luna.ps1 restart          stop + start
  .\luna.ps1 restart auth     restarts one service (auth, dashboard, pages, files, forms, nginx)
  .\luna.ps1 build [svc...]   builds images inside minikube and restarts those services
                              (all of them without names)
  .\luna.ps1 seed             db:seed --only Platform in the dashboard
  .\luna.ps1 status           minikube, the pods, the health of every host
  .\luna.ps1 logs <svc>       follows a service's log

start.bat, stop.bat and restart.bat run the first three. Hyper-V and the hosts file need an
administrator: the script asks for one (UAC) when it runs without.

nginx listens on the minikube VM's own ports 80 and 443 (hostPort, k8s/local/nginx.yaml), so
*.luna.local point at `minikube ip` in the hosts file: no tunnel, no port-forward. The VM's
address may change after a restart; start writes it again each time.
#>
param(
    [Parameter(Position = 0)][string]$Command = "status",
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Names
)

# Every kubectl call names the minikube context, so a DigitalOcean context made current by
# `doctl kubernetes cluster kubeconfig save` is never touched from here.
# Continue: Windows PowerShell turns a native command's stderr into errors, which Stop would
# make fatal; every command's exit code is checked instead (Run).
$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot
$Hosts = @("auth.luna.local", "dashboard.luna.local", "pages.luna.local", "files.luna.local", "forms.luna.local")
$Services = @("auth", "dashboard", "pages", "files", "forms")
$Known = @("auth", "dashboard", "pages", "files", "forms", "nginx", "postgres")

function Info($msg) { Write-Host "luna: $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "luna: $msg" -ForegroundColor Red; exit 1 }

function Test-Admin {
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Hyper-V and the hosts file: run again as an administrator, in a window that stays open.
function Require-Admin {
    if (Test-Admin) { return }
    Info "an administrator is needed (Hyper-V, the hosts file): asking Windows"
    $argList = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", $Command) + @($Names | Where-Object { $_ })
    Start-Process powershell -Verb RunAs -ArgumentList $argList -WorkingDirectory $Root
    exit 0
}

function Run($exe, [string[]]$a) {
    & $exe @a
    if ($LASTEXITCODE -ne 0) { Fail "$exe $($a -join ' ') failed ($LASTEXITCODE)" }
}

function Minikube-Running {
    $s = (& minikube status --format "{{.Host}}" 2>$null) -join ""
    return $s -match "Running"
}

function Use-MinikubeDocker {
    # docker in this window builds inside minikube: no `minikube image load` (which needs
    # wmic, gone from current Windows).
    & minikube -p minikube docker-env --shell powershell | Invoke-Expression
}

function Ensure-Secrets {
    $file = Join-Path $Root "k8s\local\secrets.env"
    if (Test-Path $file) { return }
    Info "k8s\local\secrets.env: generating the passwords and secrets"
    Copy-Item (Join-Path $Root "k8s\local\secrets.env.example") $file
    Push-Location (Join-Path $Root "luna-cli")
    try {
        foreach ($n in "POSTGRES_PASSWORD", "AUTH_DB_PASSWORD", "DASHBOARD_DB_PASSWORD", "PAGES_DB_PASSWORD",
            "FILES_DB_PASSWORD", "AUTH_JWT_SECRET", "LUNA_SERVICE_TOKEN") {
            Run go @("run", ".", "key:generate", "--env", "../k8s/local/secrets.env", "--name", $n)
        }
    } finally { Pop-Location }
}

function Images-Missing {
    Use-MinikubeDocker
    foreach ($img in "luna-dashboard:local", "luna-auth:local", "luna-pages:local", "luna-files:local", "luna-forms:local", "luna-nginx:local", "luna-postgres:18") {
        & docker image inspect $img *> $null
        if ($LASTEXITCODE -ne 0) { return $true }
    }
    return $false
}

function Build([string[]]$names) {
    Use-MinikubeDocker
    Push-Location $Root
    try {
        if ($names.Count -eq 0) {
            Info "building every image inside minikube"
            Run docker @("compose", "build")
        } else {
            $svc = $names | ForEach-Object { if ($_ -in "postgres", "nginx") { $_ } else { "luna-$_" } }
            Info "building $($svc -join ', ') inside minikube"
            Run docker (@("compose", "build") + $svc)
        }
    } finally { Pop-Location }
}

function Update-HostsFile {
    $ip = ((& minikube ip) -join "").Trim()
    if (-not $ip) { Fail "minikube ip gave no address" }
    $file = "$env:SystemRoot\System32\drivers\etc\hosts"
    $begin, $end = "# luna (minikube) begin", "# luna (minikube) end"
    $lines = Get-Content $file
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($l in $lines) {
        if ($l -eq $begin) { $inside = $true; continue }
        if ($l -eq $end) { $inside = $false; continue }
        if ($inside) { continue }
        # an older line for the same names (compose: 127.0.0.1) is commented out
        $parts = ($l -split "\s+") | Select-Object -Skip 1
        if (-not $l.TrimStart().StartsWith("#") -and ($parts | Where-Object { $Hosts -contains $_ })) {
            $out.Add("# $l   (luna.ps1: replaced by the minikube block)")
            continue
        }
        $out.Add($l)
    }
    $out.Add($begin)
    $out.Add("$ip  $($Hosts -join ' ')")
    $out.Add($end)
    Set-Content -Path $file -Value $out -Encoding ASCII
    & ipconfig /flushdns *> $null
    Info "hosts: $($Hosts -join ', ') -> $ip"
}

function Wait-Ready {
    Info "waiting for the services"
    foreach ($s in $Services + "nginx") {
        Run kubectl @("--context", "minikube", "-n", "luna", "rollout", "status", "deploy/luna-$s", "--timeout=300s")
    }
}

function Health {
    foreach ($h in $Hosts) {
        $r = (& curl.exe -sk --max-time 5 "https://$h/healthz") -join ""
        if ($r -match '"ok"') { Write-Host ("  {0,-24} ok" -f $h) -ForegroundColor Green }
        else { Write-Host ("  {0,-24} {1}" -f $h, ($(if ($r) { $r } else { "no answer" }))) -ForegroundColor Yellow }
    }
}

function Start-Luna {
    Require-Admin
    if (-not (Minikube-Running)) {
        Info "starting minikube"
        Run minikube @("start")
    }
    Ensure-Secrets
    if (Images-Missing) { Build @() }
    Info "applying k8s\local"
    Run kubectl @("--context", "minikube", "apply", "-k", (Join-Path $Root "k8s\local"))
    Wait-Ready
    Update-HostsFile
    Health
    Info "up: https://dashboard.luna.local (self-signed certificate)"
}

function Stop-Luna {
    Require-Admin
    Info "stopping minikube (the data stays)"
    Run minikube @("stop")
}

switch ($Command) {
    "start" { Start-Luna }
    "stop" { Stop-Luna }
    "restart" {
        if ($Names.Count -gt 0) {
            foreach ($n in $Names) {
                if ($Known -notcontains $n) { Fail "unknown service $n (auth, dashboard, pages, files, forms, nginx, postgres)" }
                $kind = if ($n -eq "postgres") { "statefulset/postgres" } else { "deploy/luna-$n" }
                Run kubectl @("--context", "minikube", "-n", "luna", "rollout", "restart", $kind)
                Run kubectl @("--context", "minikube", "-n", "luna", "rollout", "status", $kind, "--timeout=300s")
            }
        } else {
            Stop-Luna
            Start-Luna
        }
    }
    "build" {
        Require-Admin
        Build $Names
        $targets = if ($Names.Count -gt 0) { $Names } else { $Services + "nginx" }
        foreach ($n in $targets) {
            if ($n -eq "postgres") { continue } # its data: restart it on purpose (restart postgres)
            Run kubectl @("--context", "minikube", "-n", "luna", "rollout", "restart", "deploy/luna-$n")
        }
        foreach ($n in $targets) {
            if ($n -ne "postgres") { Run kubectl @("--context", "minikube", "-n", "luna", "rollout", "status", "deploy/luna-$n", "--timeout=300s") }
        }
    }
    "seed" { Run kubectl @("--context", "minikube", "-n", "luna", "exec", "deploy/luna-dashboard", "-c", "luna-dashboard", "--", "/app", "db:seed", "--only", "Platform") }
    "status" {
        & minikube status
        if (Minikube-Running) {
            & kubectl --context minikube -n luna get pods
            Health
        }
    }
    "logs" {
        if ($Names.Count -eq 0) { Fail "logs <service>" }
        & kubectl --context minikube -n luna logs -f "deploy/luna-$($Names[0])"
    }
    default { Fail "unknown command $($Command): start, stop, restart [service], build [services], seed, status, logs <service>" }
}

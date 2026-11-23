param([switch]$Background)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$backendRoot = Join-Path $projectRoot 'backend'
& (Join-Path $PSScriptRoot 'local-db.ps1') -Action stop-api
$credentials = Get-Content (Join-Path $projectRoot '.local/postgres/connection.json') -Raw | ConvertFrom-Json
if ($credentials.Host -ne '127.0.0.1' -or $credentials.Port -ne 5433 -or $credentials.Database -ne 'power_system_dev') {
    throw 'Este iniciador aceita apenas o banco local de desenvolvimento.'
}
$env:PATH = 'C:/ghcup/msys64/mingw64/bin;' + $env:PATH
$encodedPassword = [Uri]::EscapeDataString($credentials.Password)
$env:DATABASE_URL = "postgresql://power_system_dev:${encodedPassword}@127.0.0.1:5433/power_system_dev"
$env:MIGRATIONS_DIR = Join-Path $backendRoot 'migrations'
$env:STATIC_DIR = Join-Path $projectRoot 'frontend/dist'
$env:PORT = '8080'
$env:RAILWAY_ENVIRONMENT_ID = $null
$googleFile = Join-Path $projectRoot '.local/google-auth.json'
if (Test-Path $googleFile) {
    $googleConfig = Get-Content $googleFile -Raw | ConvertFrom-Json
    foreach ($key in @('GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','APP_BASE_URL')) {
        [Environment]::SetEnvironmentVariable($key, [string]$googleConfig.$key)
    }
}

# Stop only this project's server on the application port. Never stop an unrelated app.
$listeners = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue)
$owners = @($listeners | Select-Object -ExpandProperty OwningProcess -Unique)
$canonicalProcesses = @(Get-Process power-system-server -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith((Join-Path $backendRoot 'dist-db-check') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
})
$owners = @(($owners + @($canonicalProcesses | Select-Object -ExpandProperty Id)) | Sort-Object -Unique)
foreach ($ownerId in $owners) {
    $running = Get-Process -Id $ownerId -ErrorAction Stop
    if ($running.ProcessName -ne 'power-system-server' -or
        -not $running.Path.StartsWith($backendRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'A porta 8080 pertence a outro aplicativo. Nenhum processo foi encerrado.'
    }
}
foreach ($ownerId in $owners) {
    Stop-Process -Id $ownerId -Force -ErrorAction Stop
    Wait-Process -Id $ownerId -Timeout 10 -ErrorAction SilentlyContinue
}

Push-Location $backendRoot
try {
    & cabal build --builddir=dist-db-check power-system-server
    if ($LASTEXITCODE -ne 0) { throw 'O servidor não compilou; a versão antiga não será iniciada.' }
    $executable = (& cabal list-bin --builddir=dist-db-check power-system-server | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable)) { throw 'Executável do servidor não encontrado.' }
    if (-not $Background) { & $executable; return }
    $server = Start-Process -FilePath $executable -WorkingDirectory $backendRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $projectRoot '.local/backend.out.log') -RedirectStandardError (Join-Path $projectRoot '.local/backend.err.log')
    Set-Content (Join-Path $projectRoot '.local/backend.pid') $server.Id
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $server.Refresh()
        if ($server.HasExited) { throw 'O novo servidor encerrou antes de iniciar. Verifique .local/backend.err.log.' }
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:8080/api/health' -TimeoutSec 2
            $owner = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Where-Object OwningProcess -eq $server.Id)
            if ($health.database -eq 'connected' -and $owner.Count -gt 0) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    if (-not $ready) { throw 'O novo servidor não assumiu a porta 8080.' }
    Write-Host 'Servidor local atualizado e verificado na porta 8080.'
} finally { Pop-Location }

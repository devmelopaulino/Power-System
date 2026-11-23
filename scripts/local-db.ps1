param(
    [ValidateSet('start', 'stop', 'status', 'test', 'backend', 'service', 'stop-api')]
    [string]$Action = 'start',
    [string]$PostgresBin = 'C:/ghcup/msys64/mingw64/bin'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$localDirectory = Join-Path $projectRoot '.local/postgres'
$dataDirectory = Join-Path $localDirectory 'data'
$credentialsFile = Join-Path $localDirectory 'connection.json'
$passwordFile = Join-Path $localDirectory 'password.txt'
$backendDirectory = Join-Path $projectRoot 'backend'
$managedApiFile = Join-Path $projectRoot '.local/backend.pid'

# A API iniciada em segundo plano durante a preparacao pode ser retomada no terminal.
if ($Action -in @('backend', 'stop-api') -and (Test-Path $managedApiFile)) {
    $managedProcessId = 0
    if (-not [int]::TryParse((Get-Content $managedApiFile -Raw).Trim(), [ref]$managedProcessId)) { throw 'Identificador da API local invalido.' }
    $managedProcess = Get-Process -Id $managedProcessId -ErrorAction SilentlyContinue
    if ($managedProcess) {
        if ($managedProcess.ProcessName -ne 'power-system-server' -or
            -not $managedProcess.Path.StartsWith($backendDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'O identificador pertence a outro aplicativo. Nenhum processo foi interrompido.'
        }
        Stop-Process -Id $managedProcessId
    }
    Remove-Item -LiteralPath $managedApiFile
}
if ($Action -eq 'stop-api') { Write-Host 'API local gerenciada parada. APIs abertas em outros terminais devem ser encerradas com Ctrl+C.'; return }

foreach ($binary in @('initdb.exe', 'pg_ctl.exe', 'psql.exe', 'createdb.exe')) {
    if (-not (Test-Path (Join-Path $PostgresBin $binary))) {
        throw "PostgreSQL nao encontrado. Informe -PostgresBin com a pasta bin da instalacao."
    }
}
$env:PATH = $PostgresBin + [IO.Path]::PathSeparator + $env:PATH

function Invoke-Postgres([string]$Binary, [string[]]$Arguments) {
    & (Join-Path $PostgresBin $Binary) @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Falha em $Binary (codigo $LASTEXITCODE)." }
}

if ($Action -eq 'status') {
    if (-not (Test-Path (Join-Path $dataDirectory 'PG_VERSION'))) {
        Write-Host 'Banco local ainda nao preparado.'
    } else {
        & (Join-Path $PostgresBin 'pg_ctl.exe') status -D $dataDirectory
    }
    return
}
if ($Action -eq 'stop') {
    if (Test-Path (Join-Path $dataDirectory 'postmaster.pid')) {
        Invoke-Postgres 'pg_ctl.exe' @('stop', '-D', $dataDirectory, '-m', 'fast', '-w')
    } else { Write-Host 'Banco local ja esta parado.' }
    return
}
if ($env:RAILWAY_ENVIRONMENT_ID) { throw 'Este script e exclusivo do desenvolvimento local.' }

New-Item -ItemType Directory -Path $localDirectory -Force | Out-Null
if (-not (Test-Path $credentialsFile)) {
    if (Test-Path (Join-Path $dataDirectory 'PG_VERSION')) {
        throw 'Banco existente sem connection.json. Restaure as credenciais locais antes de continuar.'
    }
    $randomBytes = New-Object byte[] 32
    $randomGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $randomGenerator.GetBytes($randomBytes) } finally { $randomGenerator.Dispose() }
    $localPassword = [Convert]::ToBase64String($randomBytes)
    $credentials = [ordered]@{
        Host = '127.0.0.1'; Port = 5433; Database = 'power_system_dev'
        Username = 'power_system_dev'; Password = $localPassword
    }
    [IO.File]::WriteAllText($credentialsFile, ($credentials | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}
$credentials = Get-Content $credentialsFile -Raw | ConvertFrom-Json
# Conexao fixa ao banco deste projeto: nunca aceita URL do Railway.
if ($credentials.Host -ne '127.0.0.1' -or $credentials.Port -ne 5433 -or
    $credentials.Database -ne 'power_system_dev' -or $credentials.Username -ne 'power_system_dev') {
    throw 'Configuracao local inesperada. O script so usa 127.0.0.1:5433/power_system_dev.'
}
if (-not (Test-Path (Join-Path $dataDirectory 'PG_VERSION'))) {
    [IO.File]::WriteAllText($passwordFile, $credentials.Password + "`n", [Text.UTF8Encoding]::new($false))
    try {
        Invoke-Postgres 'initdb.exe' @('-D', $dataDirectory, '-U', $credentials.Username,
            '--auth=scram-sha-256', '--pwfile', $passwordFile, '--encoding=UTF8', '--locale=C')
    } finally {
        if (Test-Path $passwordFile) { Remove-Item -LiteralPath $passwordFile }
    }
}
& (Join-Path $PostgresBin 'pg_ctl.exe') status -D $dataDirectory *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-Postgres 'pg_ctl.exe' @('start', '-D', $dataDirectory, '-l', (Join-Path $localDirectory 'server.log'),
        '-o', '-h 127.0.0.1 -p 5433', '-w')
}

$savedPassword = $env:PGPASSWORD
$env:PGPASSWORD = $credentials.Password
try {
    $connectionArguments = @('-h', '127.0.0.1', '-p', '5433', '-U', $credentials.Username)
    $databaseExists = & (Join-Path $PostgresBin 'psql.exe') @connectionArguments -d postgres -At -v ON_ERROR_STOP=1 -c "SELECT 1 FROM pg_database WHERE datname = 'power_system_dev'"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar o banco local.' }
    if ($databaseExists -ne '1') {
        Invoke-Postgres 'createdb.exe' ($connectionArguments + @($credentials.Database))
    }
    $escapedPassword = [Uri]::EscapeDataString($credentials.Password)
    $env:DATABASE_URL = "postgresql://power_system_dev:${escapedPassword}@127.0.0.1:5433/power_system_dev"
    $env:MIGRATIONS_DIR = Join-Path $backendDirectory 'migrations'
    if ($Action -eq 'service') {
        Write-Host 'Servico PostgreSQL local pronto. Nenhuma migracao da aplicacao foi executada.'
        return
    }
    Push-Location $backendDirectory
    try {
        & cabal run --builddir=dist-db-check power-system-db
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar o esquema pelo Haskell.' }
    } finally { Pop-Location }
    Invoke-Postgres 'psql.exe' ($connectionArguments + @('-d', $credentials.Database, '-v', 'ON_ERROR_STOP=1',
        '-f', (Join-Path $backendDirectory 'test/seed-local.sql')))
    if ($Action -eq 'test') {
        Invoke-Postgres 'psql.exe' ($connectionArguments + @('-d', $credentials.Database, '-v', 'ON_ERROR_STOP=1',
            '-f', (Join-Path $backendDirectory 'test/database.sql')))
    }
} finally { $env:PGPASSWORD = $savedPassword }

Write-Host 'Banco local pronto: 127.0.0.1:5433 / power_system_dev'
Write-Host 'Credenciais para DBeaver/pgAdmin: .local/postgres/connection.json (nao enviar ao GitHub).'
$googleConfigFile = Join-Path $projectRoot '.local/google-auth.json'
if (Test-Path $googleConfigFile) {
    $googleConfig = Get-Content $googleConfigFile -Raw | ConvertFrom-Json
    foreach ($key in @('GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'APP_BASE_URL')) {
        [Environment]::SetEnvironmentVariable($key, [string]$googleConfig.$key)
    }
}
if ($Action -eq 'backend') {
    & (Join-Path $PSScriptRoot 'start-local-api.ps1')
} else {
    Write-Host 'Para iniciar a API neste terminal: cd backend; cabal run --builddir=dist-db-check power-system-server'
}

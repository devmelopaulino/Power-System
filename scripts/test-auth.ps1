param([string]$PostgresBin = 'C:/ghcup/msys64/mingw64/bin')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'local-db.ps1') -Action service -PostgresBin $PostgresBin
$credentials = Get-Content (Join-Path $projectRoot '.local/postgres/connection.json') -Raw | ConvertFrom-Json
$databaseName = 'power_system_auth_test_' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$connectionArguments = @('-h', '127.0.0.1', '-p', '5433', '-U', 'power_system_dev')
$savedPassword = $env:PGPASSWORD
$savedTestUrl = $env:AUTH_TEST_DATABASE_URL
$created = $false
$env:PGPASSWORD = $credentials.Password
try {
    & (Join-Path $PostgresBin 'createdb.exe') @connectionArguments $databaseName
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel criar o banco descartavel.' }
    $created = $true
    $escapedPassword = [Uri]::EscapeDataString($credentials.Password)
    $env:AUTH_TEST_DATABASE_URL = "postgresql://power_system_dev:${escapedPassword}@127.0.0.1:5433/$databaseName"
    Push-Location (Join-Path $projectRoot 'backend')
    try {
        & cabal test --builddir=dist-auth-check power-system-auth-test --test-show-details=direct
        if ($LASTEXITCODE -ne 0) { throw 'Os testes de autenticacao falharam.' }
    } finally { Pop-Location }
} finally {
    if ($created -and $databaseName -match '^power_system_auth_test_[a-f0-9]{10}$') {
        & (Join-Path $PostgresBin 'dropdb.exe') @connectionArguments $databaseName
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Nao foi possivel remover o banco temporario de testes.' }
    }
    $env:PGPASSWORD = $savedPassword
    $env:AUTH_TEST_DATABASE_URL = $savedTestUrl
}

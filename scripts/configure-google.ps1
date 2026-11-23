param(
    [Parameter(Mandatory = $true)] [string]$CredentialsFile,
    [string]$AppBaseUrl = 'http://localhost:5173'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$download = Get-Content -LiteralPath $CredentialsFile -Raw | ConvertFrom-Json
if (-not $download.web -or -not $download.web.client_id -or -not $download.web.client_secret) {
    throw 'Use o JSON de um cliente OAuth do tipo Aplicativo da Web, baixado do Google Cloud.'
}
$base = $AppBaseUrl.TrimEnd('/')
$uri = [Uri]$base
if (-not $uri.IsAbsoluteUri -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/' -or
    ($uri.Scheme -ne 'https' -and -not ($uri.Scheme -eq 'http' -and $uri.Host -in @('localhost', '127.0.0.1')))) {
    throw 'Informe somente a origem HTTPS do site ou http://localhost:5173 para desenvolvimento.'
}
$localDirectory = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Path $localDirectory -Force | Out-Null
$config = [ordered]@{
    GOOGLE_CLIENT_ID = $download.web.client_id
    GOOGLE_CLIENT_SECRET = $download.web.client_secret
    APP_BASE_URL = $base
}
[IO.File]::WriteAllText((Join-Path $localDirectory 'google-auth.json'), ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'Credenciais salvas em .local/google-auth.json, fora do GitHub.'
Write-Host "Confirme esta URL de retorno no Google Cloud: $base/api/auth/google/callback"
Write-Host 'Reinicie o backend com .\scripts\local-db.ps1 -Action backend.'

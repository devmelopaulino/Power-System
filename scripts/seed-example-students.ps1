param([long]$CoachId = 0)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$credentials = Get-Content (Join-Path $projectRoot '.local/postgres/connection.json') -Raw | ConvertFrom-Json
if ($credentials.Host -ne '127.0.0.1' -or $credentials.Port -ne 5433 -or $credentials.Database -ne 'power_system_dev') {
    throw 'Este script aceita apenas o banco local de desenvolvimento.'
}
$psql = 'C:/ghcup/msys64/mingw64/bin/psql.exe'
$connectionArguments = @('-h','127.0.0.1','-p','5433','-U',$credentials.Username,'-d','power_system_dev','-v','ON_ERROR_STOP=1')
$previousPassword = $env:PGPASSWORD
$env:PGPASSWORD = $credentials.Password
try {
    if ($CoachId -eq 0) {
        $owners = @(& $psql @connectionArguments -At -c "SELECT DISTINCT c.treinador_id FROM contas c JOIN sessoes s ON s.conta_sub=c.google_sub WHERE c.perfil='treinador' AND s.expires_at>CURRENT_TIMESTAMP")
        if ($LASTEXITCODE -ne 0) { throw 'Não foi possível consultar o treinador local.' }
        if ($owners.Count -ne 1) { throw 'Informe -CoachId com o identificador do treinador local que receberá os exemplos.' }
        $CoachId = [long]$owners[0]
    }
    if ($CoachId -le 0) { throw 'Identificador de treinador inválido.' }
    & $psql @connectionArguments -v "treinador_id=$CoachId" -f (Join-Path $projectRoot 'backend/test/seed-example-students.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar os alunos de exemplo.' }
    Write-Host 'Três alunos fictícios preparados no banco local. Nenhuma conta Google foi criada.'
} finally { $env:PGPASSWORD = $previousPassword }

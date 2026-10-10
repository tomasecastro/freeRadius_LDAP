#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$EnvPath = (Join-Path $PSScriptRoot '..' '.env'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ExamplePath = Join-Path $PSScriptRoot '..' '.env.example'
$Placeholder = 'CHANGE_ME'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Write-Info { param([string]$Message) Write-Host "Init-Env: $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "Init-Env: $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "Init-Env: $Message" -ForegroundColor Red }

function New-SecretBase64 {
    param([int]$ByteCount)
    $bytes = [byte[]]::new($ByteCount)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return ([Convert]::ToBase64String($bytes) -replace "`r?`n", '')
}

# 1. Crear .env desde .env.example si no existe
if (-not (Test-Path -LiteralPath $EnvPath)) {
    if (-not (Test-Path -LiteralPath $ExamplePath)) {
        Write-Err "No se encontro .env.example en $ExamplePath. No se puede crear el .env."
        exit 1
    }
    Copy-Item -LiteralPath $ExamplePath -Destination $EnvPath
    Write-Info "No existia .env; se copio .env.example -> $EnvPath"
}
else {
    Write-Info "El archivo .env ya existe: $EnvPath"
}

# 2. Crear carpetas de volumenes montadas por el compose
foreach ($dir in @('data')) {
    $full = Join-Path $ProjectRoot $dir
    if (-not (Test-Path -LiteralPath $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
        Write-Info "Carpeta creada: ./$dir"
    }
}

# 3. Generar secretos idempotente
$lines = [System.Collections.Generic.List[string]]::new()
Get-Content -LiteralPath $EnvPath | ForEach-Object { [void]$lines.Add($_) }

$generated = [System.Collections.Generic.List[string]]::new()
$preserved = [System.Collections.Generic.List[string]]::new()

function Resolve-Secret {
    param(
        [string]$Name,
        [int]$ByteCount,
        [System.Collections.Generic.List[string]]$Lines
    )
    $index = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Name))\s*=") { $index = $i; break }
    }

    if ($index -ge 0) {
        $current = ($Lines[$index] -split '=', 2)[1]
        $isPlaceholder = ($null -eq $current) -or ($current.Trim() -eq '') -or ($current.Trim() -like "$Placeholder*")
        if (-not $isPlaceholder -and -not $Force) {
            Write-Warn "$Name ya tiene un valor real; se preserva (usa -Force para regenerarlo)."
            $preserved.Add($Name) | Out-Null
            return
        }
        $secret = New-SecretBase64 -ByteCount $ByteCount
        $Lines[$index] = "$Name=$secret"
        Write-Info "$Name generado ($($secret.Length) caracteres)."
        $generated.Add($Name) | Out-Null
        return
    }

    $secret = New-SecretBase64 -ByteCount $ByteCount
    $Lines.Add("$Name=$secret") | Out-Null
    Write-Info "$Name generado y agregado ($($secret.Length) caracteres)."
    $generated.Add($Name) | Out-Null
}

Resolve-Secret -Name 'MYSQL_PASSWORD' -ByteCount 36 -Lines $lines
Resolve-Secret -Name 'MYSQL_ROOT_PASSWORD' -ByteCount 36 -Lines $lines
Resolve-Secret -Name 'DEFAULT_CLIENT_SECRET' -ByteCount 36 -Lines $lines

# 4. Reescribir preservando orden y comentarios
Set-Content -LiteralPath $EnvPath -Value $lines -Encoding utf8NoBOM

Write-Host ''
Write-Info "Variables generadas: $(if ($generated.Count) { $generated -join ', ' } else { 'ninguna' })"
Write-Info "Variables preservadas: $(if ($preserved.Count) { $preserved -join ', ' } else { 'ninguna' })"
Write-Info 'Los valores de los secretos NO se imprimen por seguridad.'
Write-Info 'Siguiente paso: docker compose pull && docker compose up -d'

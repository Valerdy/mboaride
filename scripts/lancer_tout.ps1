# Lance MboaRide de bout en bout sur un PC Windows : base PostgreSQL, API Node (connexion,
# itinéraires), API Python (métier, moteur d'agents, console web), et rend les deux API
# joignables depuis les téléphones Android branchés (adb reverse).
#
#   powershell -ExecutionPolicy Bypass -File scripts\lancer_tout.ps1
#
# Réglages dans .env.local à la racine du dépôt (jamais commité, voir .env.local.example) :
#   PG_HOST, PG_PORT, PG_USER, PG_PASSWORD   PostgreSQL déjà installé sur le PC
#   SECRET_KEY                               secret partagé par les deux API (généré au besoin)
# Mode d'emploi complet : docs/demarrage-local.md

$ErrorActionPreference = 'Stop'
$Racine = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Racine 'backend'
$Node = Join-Path $Backend 'mboaride-api-node(1)'
$EnvLocal = Join-Path $Racine '.env.local'
$PortApi = 8000
$PortAuth = 8101

function Etape($texte) { Write-Host "`n== $texte" -ForegroundColor Green }

# --- 1. Réglages ------------------------------------------------------------------------------
Etape 'Réglages (.env.local)'
if (-not (Test-Path $EnvLocal)) {
    Copy-Item (Join-Path $Racine '.env.local.example') $EnvLocal
    Write-Host "Fichier .env.local créé. Renseignez PG_PASSWORD (mot de passe de l'utilisateur postgres), puis relancez." -ForegroundColor Yellow
    exit 1
}
$conf = @{}
foreach ($ligne in Get-Content $EnvLocal -Encoding UTF8) {
    if ($ligne -match '^\s*([A-Z_]+)\s*=\s*(.*)\s*$') { $conf[$Matches[1]] = $Matches[2] }
}
if (-not $conf['PG_PASSWORD']) { Write-Host 'PG_PASSWORD est vide dans .env.local.' -ForegroundColor Yellow; exit 1 }
foreach ($cle in 'PG_HOST', 'PG_PORT', 'PG_USER') {
    if (-not $conf[$cle]) { $conf[$cle] = @{ PG_HOST = '127.0.0.1'; PG_PORT = '5432'; PG_USER = 'postgres' }[$cle] }
}
if (-not $conf['SECRET_KEY'] -or $conf['SECRET_KEY'].Length -lt 32) {
    $octets = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($octets)
    $conf['SECRET_KEY'] = [Convert]::ToBase64String($octets).Replace('+', '-').Replace('/', '_').TrimEnd('=')
    Add-Content $EnvLocal "SECRET_KEY=$($conf['SECRET_KEY'])" -Encoding UTF8
    Write-Host 'Secret partagé généré et ajouté à .env.local.'
}
foreach ($cle in 'PG_HOST', 'PG_PORT', 'PG_USER', 'PG_PASSWORD') { Set-Item "env:$cle" $conf[$cle] }
# Code de vérification : par e-mail (Gmail) si SMTP_USER et SMTP_PASS sont remplis. Sinon le
# code reste dans la console de l'API Node et s'affiche dans l'application (démonstration).
foreach ($cle in 'OTP_CHANNEL', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS') { if (-not $conf[$cle]) { $conf[$cle] = '' } }
if (-not $conf['OTP_CHANNEL']) { $conf['OTP_CHANNEL'] = 'email' }
if (-not $conf['SMTP_HOST']) { $conf['SMTP_HOST'] = 'smtp.gmail.com' }
if (-not $conf['SMTP_PORT']) { $conf['SMTP_PORT'] = '587' }
$emailActif = [bool]($conf['SMTP_USER'] -and $conf['SMTP_PASS'])
$conf['EXPOSE_DEV_CODE'] = if ($emailActif) { '0' } else { '1' }
if ($emailActif) { Write-Host "Codes de vérification envoyés par e-mail depuis $($conf['SMTP_USER'])." } else {
    Write-Host 'Codes de vérification : pas de SMTP_USER / SMTP_PASS dans .env.local, le code reste dans la console.' -ForegroundColor Yellow
}
$env:PG_DATABASE = 'mboaride'

# --- 2. Environnement Python ---------------------------------------------------------------------
Etape 'Environnement Python (backend\.venv)'
$Py = Join-Path $Backend '.venv\Scripts\python.exe'
if (-not (Test-Path $Py)) {
    $lanceur = Get-Command py -ErrorAction SilentlyContinue
    if ($lanceur) { & py -3 -m venv (Join-Path $Backend '.venv') } else { & python -m venv (Join-Path $Backend '.venv') }
}
& $Py -m pip install --quiet --disable-pip-version-check -r (Join-Path $Backend 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Installation des dépendances Python impossible' }

# --- 3. Base de données ------------------------------------------------------------------------
Etape 'Base PostgreSQL partagée'
& $Py (Join-Path $Racine 'scripts\preparer_base.py')
if ($LASTEXITCODE -ne 0) { exit 1 }

# --- 4. API Node -----------------------------------------------------------------------------------
Etape "API Node : connexion et itinéraires (port $PortAuth)"
if (-not (Test-Path (Join-Path $Node 'node_modules'))) {
    Push-Location $Node
    try { & npm install --no-audit --no-fund } finally { Pop-Location }
}
$mdp = [Uri]::EscapeDataString($conf['PG_PASSWORD'])
$urlBase = "postgres://$($conf['PG_USER']):$mdp@$($conf['PG_HOST']):$($conf['PG_PORT'])/mboaride"
# Les variables du processus priment sur un éventuel fichier .env de l'API Node.
$cmdNode = @"
`$Host.UI.RawUI.WindowTitle = 'MboaRide - API Node ($PortAuth)'
`$env:DATABASE_URL = '$urlBase'
`$env:SECRET_KEY = '$($conf['SECRET_KEY'])'
`$env:PORT = '$PortAuth'
`$env:EXPOSE_DEV_CODE = '$($conf['EXPOSE_DEV_CODE'])'
`$env:OTP_CHANNEL = '$($conf['OTP_CHANNEL'])'
`$env:SMTP_HOST = '$($conf['SMTP_HOST'])'
`$env:SMTP_PORT = '$($conf['SMTP_PORT'])'
`$env:SMTP_USER = '$($conf['SMTP_USER'])'
`$env:SMTP_PASS = '$($conf['SMTP_PASS'].Replace("'", "''"))'
`$env:ACCESS_TOKEN_MINUTES = '720'
`$env:OSRM_URL = 'https://router.project-osrm.org'
`$env:OSRM_TIMEOUT_MS = '12000'  # le serveur public met plusieurs secondes depuis le Cameroun
Set-Location -LiteralPath '$Node'
npm run dev
"@
Start-Process powershell -ArgumentList '-NoExit', '-Command', $cmdNode

# --- 5. API Python ---------------------------------------------------------------------------------
Etape "API Python : métier, moteur d'agents et console web (port $PortApi)"
$dsn = "host=$($conf['PG_HOST']) port=$($conf['PG_PORT']) user=$($conf['PG_USER']) password=$($conf['PG_PASSWORD']) dbname=mboaride"
# Même compte Gmail que les codes : les messages envoyés depuis la console d'administration
# partent aussi par e-mail (sinon ils sont seulement enregistrés, « simulés »).
$smtpPy = ''
if ($emailActif) {
    $smtpPy = @"
`$env:MBOARIDE_SMTP_HOST = '$($conf['SMTP_HOST'])'
`$env:MBOARIDE_SMTP_PORT = '$($conf['SMTP_PORT'])'
`$env:MBOARIDE_SMTP_USER = '$($conf['SMTP_USER'])'
`$env:MBOARIDE_SMTP_PASSWORD = '$(($conf['SMTP_PASS'] -replace '\s', '').Replace("'", "''"))'
"@
}
$cmdPy = @"
`$Host.UI.RawUI.WindowTitle = 'MboaRide - API Python ($PortApi)'
`$env:MBOARIDE_DSN = '$($dsn.Replace("'", "''"))'
`$env:MBOARIDE_SECRET_KEY = '$($conf['SECRET_KEY'])'
`$env:MBOARIDE_AGREMENT_AUTO = '1'
`$env:MBOARIDE_SIMULATION = '1'
$smtpPy
Set-Location -LiteralPath '$Backend'
& '$Py' -m uvicorn app.main:app --host 127.0.0.1 --port $PortApi
"@
Start-Process powershell -ArgumentList '-NoExit', '-Command', $cmdPy

# --- 6. Attente des deux API ------------------------------------------------------------------------
Etape 'Attente des deux API'
foreach ($url in "http://127.0.0.1:$PortAuth/health", "http://127.0.0.1:$PortApi/health") {
    $pret = $false
    for ($i = 0; $i -lt 60 -and -not $pret; $i++) {
        try { Invoke-RestMethod $url -TimeoutSec 2 | Out-Null; $pret = $true } catch { Start-Sleep -Seconds 1 }
    }
    if ($pret) { Write-Host "OK   $url" } else { Write-Host "PAS DE RÉPONSE   $url (voir sa fenêtre)" -ForegroundColor Red }
}

# --- 7. Téléphones Android -------------------------------------------------------------------------
Etape 'Téléphones et émulateurs Android (adb reverse)'
$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb -and $env:ANDROID_HOME) { $adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }
$appareils = @()
if ($adb) {
    $appareils = & $adb devices | Select-String '^\S+\s+device$' | ForEach-Object { ($_ -split '\s+')[0] }
    foreach ($a in $appareils) {
        & $adb -s $a reverse "tcp:$PortApi" "tcp:$PortApi" | Out-Null
        & $adb -s $a reverse "tcp:$PortAuth" "tcp:$PortAuth" | Out-Null
        Write-Host "$a : 127.0.0.1:$PortApi et 127.0.0.1:$PortAuth renvoient vers ce PC"
    }
}
if (-not $appareils) {
    Write-Host 'Aucun appareil Android prêt. Branchez le téléphone (débogage USB autorisé) ou démarrez l''émulateur, puis relancez ce script ou : scripts\relier_android.ps1' -ForegroundColor Yellow
}

Write-Host @"

MboaRide tourne.
  Console web (navigateur) : http://localhost:$PortApi        documentation de l'API : http://localhost:$PortApi/docs
  Administration MboaRide   : http://localhost:$PortApi/admin  (premier admin : scripts\creer_admin.py <e-mail>)
  Codes de vérification     : affichés dans l'application et dans la fenêtre « API Node »

Applications (dans frontend\mboaride_flutter_project) :
  Chauffeur, téléphone : flutter run -d 2B241FDH3000YX --dart-define=API_URL=http://127.0.0.1:$PortApi --dart-define=AUTH_URL=http://127.0.0.1:$PortAuth --dart-define=START=driver
  Client, émulateur    : flutter run -d emulator-5554 --dart-define=API_URL=http://127.0.0.1:$PortApi --dart-define=AUTH_URL=http://127.0.0.1:$PortAuth
"@

# Lance les deux applications MboaRide : le client sur le téléphone branché, le chauffeur sur
# l'émulateur (l'émulateur est démarré au besoin). À lancer APRÈS scripts\lancer_tout.ps1,
# ou en une seule commande : scripts\lancer_tout.ps1 -Apps
#
#   powershell -ExecutionPolicy Bypass -File scripts\lancer_apps.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\lancer_apps.ps1 -Inverser   # client sur l'émulateur
#
# Chaque application s'ouvre dans sa propre fenêtre « flutter run » (r = recharger, q = quitter).

param(
    [switch]$Inverser,          # client sur l'émulateur, chauffeur sur le téléphone
    [string]$Avd = ''           # nom de l'émulateur (par défaut : le premier de la liste)
)

$ErrorActionPreference = 'Stop'
$Racine = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Racine 'frontend\mboaride_flutter_project'
$Sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $Adb) { $Adb = Join-Path $Sdk 'platform-tools\adb.exe' }
$Emulateur = Join-Path $Sdk 'emulator\emulator.exe'

function Etape($texte) { Write-Host "`n== $texte" -ForegroundColor Green }
function Appareils { & $Adb devices | Select-String '^\S+\s+device$' | ForEach-Object { ($_ -split '\s+')[0] } }

# --- 1. Émulateur --------------------------------------------------------------------------------
Etape 'Émulateur'
if (-not (Appareils | Where-Object { $_ -like 'emulator-*' })) {
    if (-not $Avd) { $Avd = (& $Emulateur -list-avds | Select-Object -First 1) }
    if (-not $Avd) { throw "Aucun émulateur Android trouvé (Android Studio > Device Manager)." }
    Write-Host "Démarrage de $Avd (une à deux minutes)..."
    Start-Process $Emulateur -ArgumentList '-avd', $Avd, '-no-snapshot-save'
    for ($i = 0; $i -lt 120; $i++) {
        $emu = Appareils | Where-Object { $_ -like 'emulator-*' } | Select-Object -First 1
        if ($emu -and ((& $Adb -s $emu shell getprop sys.boot_completed 2>$null) -match '1')) { break }
        Start-Sleep -Seconds 3
    }
}
$emu = Appareils | Where-Object { $_ -like 'emulator-*' } | Select-Object -First 1
$tel = Appareils | Where-Object { $_ -notlike 'emulator-*' } | Select-Object -First 1
if (-not $emu) { throw "L'émulateur ne répond pas." }
Write-Host "Émulateur : $emu"
if ($tel) { Write-Host "Téléphone : $tel" } else { Write-Host "Aucun téléphone branché (débogage USB autorisé ?) : les deux applications iront sur l'émulateur." -ForegroundColor Yellow; $tel = $emu }

# --- 2. Liaison avec le PC -------------------------------------------------------------------------
Etape 'Liaison avec les API (adb reverse)'
& (Join-Path $PSScriptRoot 'relier_android.ps1')

# --- 3. Les deux applications --------------------------------------------------------------------
Etape 'Applications'
$cibleClient = if ($Inverser) { $emu } else { $tel }
$cibleChauffeur = if ($Inverser) { $tel } else { $emu }
$defs = '--dart-define=API_URL=http://127.0.0.1:8000 --dart-define=AUTH_URL=http://127.0.0.1:8101'

function Lancer($titre, $appareil, $extra) {
    $cmd = "`$Host.UI.RawUI.WindowTitle = '$titre'; Set-Location -LiteralPath '$App'; flutter run -d $appareil $defs $extra"
    Start-Process powershell -ArgumentList '-NoExit', '-Command', $cmd
    Write-Host "$titre sur $appareil"
}
Lancer 'MboaRide - Client' $cibleClient ''
Lancer 'MboaRide - Chauffeur' $cibleChauffeur '--dart-define=START=driver'

Write-Host "`nLa première compilation prend quelques minutes. Les applications s'ouvrent toutes seules." -ForegroundColor Green

<#
.SYNOPSIS
    Fait rouler le GPS de l'émulateur Android le long d'une vraie route de Douala.

.DESCRIPTION
    Pour essayer le suivi de course sans se déplacer : le script demande l'itinéraire à
    OSRM (OpenStreetMap), puis envoie à l'émulateur une position par seconde avec
    « adb emu geo fix ». Dans MboaRide, laissez le mode « GPS » de l'écran de suivi : la
    carte avance avec la position, et l'arrivée à moins de 80 m de la destination ouvre
    l'écran de fin de course (merci, note, commentaire).

    Sur un vrai téléphone, utilisez plutôt le mode « Simulation » de l'écran de suivi.

.EXAMPLE
    .\scripts\simuler_gps_emulateur.ps1 -De Logpom -A Bonaberi
    .\scripts\simuler_gps_emulateur.ps1 -De "4.0720,9.7660" -A Bonanjo -Acceleration 10
#>
param(
    [string]$De = 'Kotto',
    [string]$A = 'Bonanjo',
    [double]$VitesseKmh = 30,
    [double]$Acceleration = 5,
    [string]$Appareil = 'emulator-5554',
    [double]$PasSecondes = 1
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# Mêmes quartiers que l'application (lat, lon).
$lieux = @{
    'logpom'       = @(4.0846, 9.7562)
    'kotto'        = @(4.0720, 9.7660)
    'bonanjo'      = @(4.0435, 9.6908)
    'akwa'         = @(4.0511, 9.7011)
    'bonapriso'    = @(4.0267, 9.7019)
    'makepe'       = @(4.0753, 9.7423)
    'ndokoti'      = @(4.0489, 9.7431)
    'deido'        = @(4.0619, 9.7128)
    'bonamoussadi' = @(4.0892, 9.7385)
    'yassa'        = @(4.0086, 9.8114)
    'bonaberi'     = @(4.0764, 9.6644)
}

function Get-Coordonnees([string]$texte) {
    if ($texte -match '^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$') {
        return @([double]::Parse($Matches[1], $inv), [double]::Parse($Matches[2], $inv))
    }
    $cle = $texte.ToLowerInvariant().Replace('é', 'e').Replace('è', 'e').Trim()
    if (-not $lieux.ContainsKey($cle)) {
        throw "Lieu inconnu : $texte. Connus : $($lieux.Keys -join ', '), ou « lat,lon »."
    }
    return $lieux[$cle]
}

function Get-Distance($a, $b) {
    # Haversine, en mètres ; a et b = @(lat, lon)
    $r = 6371000.0
    $dLat = ($b[0] - $a[0]) * [Math]::PI / 180
    $dLon = ($b[1] - $a[1]) * [Math]::PI / 180
    $h = [Math]::Sin($dLat / 2) * [Math]::Sin($dLat / 2) +
         [Math]::Cos($a[0] * [Math]::PI / 180) * [Math]::Cos($b[0] * [Math]::PI / 180) *
         [Math]::Sin($dLon / 2) * [Math]::Sin($dLon / 2)
    return 2 * $r * [Math]::Asin([Math]::Sqrt($h))
}

$depart = Get-Coordonnees $De
$arrivee = Get-Coordonnees $A
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'adb' }

$coords = '{0},{1};{2},{3}' -f $depart[1].ToString($inv), $depart[0].ToString($inv), $arrivee[1].ToString($inv), $arrivee[0].ToString($inv)
Write-Host "Itinéraire $De -> $A (OSRM)..."
$reponse = Invoke-RestMethod "https://router.project-osrm.org/route/v1/driving/$($coords)?overview=full&geometries=geojson" -TimeoutSec 30
if ($reponse.code -ne 'Ok') { throw "OSRM n'a pas d'itinéraire : $($reponse.code)" }
$trace = @($reponse.routes[0].geometry.coordinates | ForEach-Object { , @([double]$_[1], [double]$_[0]) })
$longueur = $reponse.routes[0].distance
$pas = $VitesseKmh / 3.6 * $Acceleration * $PasSecondes
Write-Host ("{0:N1} km, une position tous les {1:N0} m ({2} km/h x{3}) sur {4}." -f ($longueur / 1000), $pas, $VitesseKmh, $Acceleration, $Appareil)

function Send-Position($p) {
    $lon = $p[1].ToString('F6', $inv)
    $lat = $p[0].ToString('F6', $inv)
    & $adb -s $Appareil emu geo fix $lon $lat | Out-Null   # longitude d'abord
}

$parcouru = 0.0
$prochain = 0.0
Send-Position $trace[0]
for ($i = 1; $i -lt $trace.Count; $i++) {
    $a = $trace[$i - 1]; $b = $trace[$i]
    $segment = Get-Distance $a $b
    while ($prochain -le $parcouru + $segment) {
        $t = if ($segment -gt 0) { ($prochain - $parcouru) / $segment } else { 0 }
        $p = @(($a[0] + ($b[0] - $a[0]) * $t), ($a[1] + ($b[1] - $a[1]) * $t))
        Send-Position $p
        Write-Progress -Activity "Trajet $De -> $A" -Status ("{0:N1} km sur {1:N1}" -f ($prochain / 1000), ($longueur / 1000)) -PercentComplete ([Math]::Min(100, 100 * $prochain / $longueur))
        Start-Sleep -Milliseconds ([int]($PasSecondes * 1000))
        $prochain += $pas
    }
    $parcouru += $segment
}
Send-Position $trace[-1]
Write-Progress -Activity "Trajet $De -> $A" -Completed
Write-Host "Arrivé à $A : l'application doit afficher la fin de course."

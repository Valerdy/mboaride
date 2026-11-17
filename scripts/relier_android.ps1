# Rend les deux API du PC joignables en 127.0.0.1 depuis chaque téléphone ou émulateur
# Android branché : à relancer après avoir branché un appareil ou démarré l'émulateur.
#   powershell -ExecutionPolicy Bypass -File scripts\relier_android.ps1

$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb -and $env:ANDROID_HOME) { $adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }
if (-not $adb) { Write-Host 'adb introuvable : installez les outils Android (Android Studio).'; exit 1 }
$appareils = & $adb devices | Select-String '^\S+\s+device$' | ForEach-Object { ($_ -split '\s+')[0] }
if (-not $appareils) {
    Write-Host 'Aucun appareil prêt. Un téléphone « unauthorized » attend que vous acceptiez le débogage USB à l''écran.'
    & $adb devices
    exit 1
}
foreach ($a in $appareils) {
    & $adb -s $a reverse tcp:8000 tcp:8000 | Out-Null
    & $adb -s $a reverse tcp:8101 tcp:8101 | Out-Null
    Write-Host "$a : 127.0.0.1:8000 (API Python) et 127.0.0.1:8101 (API Node) renvoient vers ce PC"
}

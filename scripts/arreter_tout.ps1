# Arrête les deux API de MboaRide lancées par scripts\lancer_tout.ps1 (fenêtres « MboaRide - API
# Node » et « MboaRide - API Python », ports 8101 et 8000). PostgreSQL, l'émulateur et le
# téléphone ne sont pas touchés.
#   powershell -ExecutionPolicy Bypass -File scripts\arreter_tout.ps1

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'MboaRide - API' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

foreach ($port in 8000, 8101) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
}

Start-Sleep -Seconds 1
foreach ($port in 8000, 8101) {
    $libre = -not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    Write-Host ("Port {0} : {1}" -f $port, $(if ($libre) { 'arrêté' } else { 'encore occupé' }))
}

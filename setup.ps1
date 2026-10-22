# Baixa o Android Platform Tools (adb.exe) oficial do Google e extrai
# para a pasta platform-tools, ao lado deste script. So precisa rodar uma
# vez por notebook.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DestDir = Join-Path $ScriptDir "platform-tools"
$ZipPath = Join-Path $ScriptDir "platform-tools.zip"
$Url = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"

if (Test-Path (Join-Path $DestDir "adb.exe")) {
    Write-Output "adb.exe ja existe em $DestDir - nada a fazer."
    exit 0
}

Write-Output "Baixando Android Platform Tools (adb.exe) do Google..."
Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing

Write-Output "Extraindo..."
Expand-Archive -Path $ZipPath -DestinationPath $ScriptDir -Force
Remove-Item $ZipPath

if (Test-Path (Join-Path $DestDir "adb.exe")) {
    Write-Output "Pronto! adb.exe instalado em $DestDir"
} else {
    Write-Output "ERRO: nao foi possivel confirmar a instalacao do adb.exe."
    exit 1
}

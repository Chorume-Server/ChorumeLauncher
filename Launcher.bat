@echo off

set "scriptUrl=https://raw.githubusercontent.com/gcmarcello/ChorumeLauncher/refs/heads/main/script.ps1"

set "tempFile=%TEMP%\script-CHRMSRVR.ps1"

echo Baixando o script %scriptUrl%...
powershell -NoProfile -Command ^
    "try { " ^
        "Invoke-WebRequest -Uri '%scriptUrl%' -OutFile '%tempFile%' -UseBasicParsing; " ^
        "Write-Host 'Script baixado com sucesso %tempFile%'; " ^
        "Write-Host 'Executando...'; " ^
        "& '%tempFile%'; " ^
    "} catch { " ^
        "Write-Error 'Falha ao baixar ou executar o script: $_'; " ^
    "} finally { " ^
        "if (Test-Path '%tempFile%') { " ^
            "Remove-Item -Path '%tempFile%' -Force; " ^
            "Write-Host 'Arquivo temporario removido'; " ^
        "} " ^
    "}"

if exist "%tempFile%" (
    del "%tempFile%"
    echo Arquivo temporario removido.
)

echo Done.
exit

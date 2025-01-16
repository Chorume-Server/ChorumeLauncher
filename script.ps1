# Variables
$OutputEncoding = [System.Text.Encoding]::UTF8
$AppDataPath = "$env:APPDATA\.minecraft"
$TLauncherPath = "$env:APPDATA\.tlauncher"
$TLauncherPropertiesPath = "$TLauncherPath\tlauncher-2.0.properties"
$ModsFolder = "$AppDataPath\mods"
$GitRemoteRepo = "https://github.com/chorumeserver/Mods-CHRSRV.git"
$global:HasInstalledTLauncher = $false



function Get-FileWithProgress {
    param (
        [string]$Url,
        [string]$OutFile
    )

    # Hide the cursor
    [System.Console]::CursorVisible = $false

    $uri = New-Object "System.Uri" "$Url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000) # 15 second timeout

    $response = $request.GetResponse()
    $totalLength = [System.Math]::Floor($response.get_ContentLength() / 1024)  # Total size in KB

    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $OutFile, Create
    $buffer = new-object byte[] 1000KB

    $count = $responseStream.Read($buffer, 0, $buffer.length)
    $downloadedBytes = $count

    # Print the initial status or any previous messages
    Write-Host "Baixando '$($Url.split('/') | Select-Object -Last 1)'"

    # Loop until the file is fully downloaded
    while ($count -gt 0) {
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer, 0, $buffer.length)
        $downloadedBytes = $downloadedBytes + $count

        # Calculate the progress
        $progress = "Progresso: ($([System.Math]::Floor($downloadedBytes / 1024))K of $($totalLength)K): "
        $percentComplete = [math]::round(($downloadedBytes / $response.ContentLength) * 100)

        # Move the cursor to the beginning of the line
        Write-Host -NoNewline "$progress $percentComplete% completo"

        # Use carriage return to overwrite the previous line
        Write-Host -NoNewline "`r"
    }

    # Show the cursor again after download is complete
    [System.Console]::CursorVisible = $true

    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

function Get-ProcessRunning {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    return $null -ne $process
}

function Watch-ProcessRunningAndStopping {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $false)]
        [string]$Log
    )

    while (-Not (Get-ProcessRunning -ProcessName $ProcessName)) {
        if ($Log) {
            Write-Host "Waiting for process '$ProcessName' to start..."
        }
        
        Start-Sleep -Seconds 2
    }

    while ((Get-ProcessRunning -ProcessName $ProcessName)) {
        if ($Log) {
            Write-Host "Waiting for process '$ProcessName' to stop..."
        }
        Start-Sleep -Seconds 2
    }

}

function Stop-ProcessByName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    try {
        $process = Get-Process -Name $ProcessName -ErrorAction Stop
        $process | ForEach-Object { $_.Kill() }
        Write-Host "Process '$ProcessName' has been killed."
    }
    catch {
        Write-Host "Process '$ProcessName' not found or could not be terminated. $_" -ForegroundColor Red
    }
}

function Invoke-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host $Message -ForegroundColor Red
    Read-Host -Prompt "Pressione Enter para sair"
    exit 1
}

function Send-Msg {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Error", "Success", "Warning")]
        [string]$Variant
    )

    switch ($Variant) {
        "Error" {
            Write-Host " - $Message" -ForegroundColor Red
        }
        "Success" {
            Write-Host " - $Message" -ForegroundColor Green
        }
        "Warning" {
            Write-Host " - $Message" -ForegroundColor Yellow
        }
    }
}

function Get-GitInstallation {
    try {
        git --version > $null 2>&1
        return $true
    }
    catch {
        return $false
    }
}

function Install-Git {
    $git_latest_executable_download_url = "https://github.com/git-for-windows/git/releases/download/v2.41.0.windows.1/Git-2.41.0-64-bit.exe"
    $git_latest_executable = "$env:TEMP\Git-64-bit.exe"

    try {
        if (-Not(Test-Path $git_latest_executable)) {
            Send-Msg -Message "Git nao instalado, fazendo download..." -Variant "Warning"
            Get-FileWithProgress -Url $git_latest_executable_download_url -OutFile $git_latest_executable
        }
        Send-Msg -Message "Atualizando Git..." -Variant "Success"
        Start-Process -FilePath $git_latest_executable -ArgumentList "/VERYSILENT", "/NORESTART" -Wait
        Start-Sleep -Seconds 5
        Send-Msg -Message "Git Atualizado" -Variant "Success"
    }
    catch {
        Invoke-Error -Message "Falha ao baixar o Git. Erro: $_"
    }
}

function Get-TLauncherInstallation {
    if (Test-Path -Path $TLauncherPath) {
        return $true
    }
    else {
        return $false
    }
}

function Install-TLauncher {
    Send-Msg -Message "Pasta .tlauncher nao encontrada. Baixando o TLauncher." -Variant "Warning"
    $TLauncherInstallerPath = "$env:TEMP\TLauncher-Installer-1.6.0.exe"
    if (Test-Path $TLauncherInstallerPath) {
        Send-Msg -Message "TLauncher ja baixado. Executando o instalador..." -Variant "Success"
        Send-Msg -Message "VOCE SERA REDIRECIONADO A INSTALACAO. NO FIM, MARQUE A OPCAO DE INICIAR O LAUNCHER, CASO CONTRARIO NAO IRA FUNCIONAR" -Variant "Error"
        Write-Host "PRESSIONE ENTER PARA CONTINUAR" -ForegroundColor Red
        Read-Host
        Send-Msg -Message "Aguardando instalacao do TLauncher..." -Variant "Warning"
        Start-Process -FilePath $TLauncherInstallerPath
        Watch-ProcessRunningAndStopping -ProcessName "TLauncher-Installer-1.6.0"
    }
    else {
        try {
            Get-FileWithProgress -Url "https://dl2.tlauncher.org/f.php?f=files%2FTLauncher-Installer-1.6.0.exe" -OutFile $TLauncherInstallerPath
            Send-Msg -Message "TLauncher baixado com sucesso. Executando o instalador" -Variant "Success"
            Send-Msg -Message "VOCE SERA REDIRECIONADO A INSTALACAO. NO FIM, MARQUE A OPCAO DE INICIAR O LAUNCHER, CASO CONTRARIO NAO IRA FUNCIONAR" -Variant "Error"
            Write-Host "PRESSIONE ENTER PARA CONTINUAR" -ForegroundColor Red
            Read-Host
            Start-Process -FilePath $TLauncherInstallerPath
            Watch-ProcessRunningAndStopping -ProcessName "TLauncher-Installer-1.6.0"
        }
        catch {
            Send-Msg -Message "Falha ao baixar o TLauncher. Erro: $_" -Variant "Error"
        }
    }
    $LauncherProccessName = "java"
    $UpdaterProcessName = "javaw"
    Send-Msg -Message "Aguardando atualizacao do TLauncher..." -Variant "Warning"
    Watch-ProcessRunningAndStopping -ProcessName $UpdaterProcessName
    Send-Msg -Message "Aguardando inicializacao do TLauncher..." -Variant "Warning"
    while ((Get-ProcessRunning -ProcessName $UpdaterProcessName) -and (Get-ProcessRunning -ProcessName $LauncherProccessName)) {
        Start-Sleep -Seconds 2
    }
    Stop-ProcessByName -ProcessName $LauncherProccessName
}

function Update-TLauncher {
    if (Test-Path -Path $TLauncherPropertiesPath) {
        $Properties = Get-Content -Path $TLauncherPropertiesPath
        $UpdatedProperties = $Properties -replace 'login.version.game=.*', ''
        $UpdatedProperties += "login.version.game=Fabric 1.20.1"
        Set-Content -Path $TLauncherPropertiesPath -Value $UpdatedProperties
        Send-Msg -Message "Versao do Fabric corrigida" -Variant "Success"
    }
    else {
        Send-Msg -Message "TLauncher nao inicializado corretamente. Por favor, tente reinstalar." -Variant "Error"
        Read-Host -Prompt "Pressione Enter para sair"
        exit 1
    }
    Send-Msg -Message "TLauncher configurado. Iniciando..." -Variant "Success"
}

function Get-GitRepo {
    if (Test-Path -Path "$ModsFolder\.git") {
        Send-Msg -Message "Repositorio Git encontrado na pasta de mods." -Variant "Success"
    }
    else {
        Send-Msg -Message "Nenhum repositorio Git encontrado na pasta de mods." -Variant "Warning"
    }
}

function New-GitRepo {
    Send-Msg -Message "Inicializando repositorio Git na pasta de mods..." -Variant "Warning"
    git init $ModsFolder
    Send-Msg -Message "Repositorio Git inicializado." -Variant "Success"
    Send-Msg -Message "Adicionando repositorio remoto..." -Variant "Warning"
    & git -C $ModsFolder remote add origin $GitRemoteRepo
    Send-Msg -Message "Repositório remoto adicionado." -Variant "Success"
}

function Update-GitRepo {
    Send-Msg -Message "Atualizando repositorio remoto..." -Variant "Warning"
    & git -C $ModsFolder reset --hard HEAD
    Send-Msg -Message "Repositorio remoto atualizado." -Variant "Success"
}

function Show-RainbowAscii {
    $asciiArt = @"

 _____ _                                       _____                          
/  __ \ |                                     /  ___|                         
| /  \/ |__   ___  _ __ _   _ _ __ ___   ___  \ `--.  ___ _ ____   _____ _ __ 
| |   | '_ \ / _ \| '__| | | | '_ ` _ \ / _ \  `--. \/ _ \ '__\ \ / / _ \ '__|
| \__/\ | | | (_) | |  | |_| | | | | | |  __/ /\__/ /  __/ |   \ V /  __/ |   
 \____/_| |_|\___/|_|   \__,_|_| |_| |_|\___| \____/ \___|_|    \_/ \___|_|   
                                                                              
                                                                              
"@
    
    # Split the ASCII art into lines
    $asciiArtLines = $asciiArt -split "`n"
    
    # Create a rainbow effect for each line
    $rainbowColors = @(
        "Red", "Yellow", "DarkYellow", "Green", "Cyan", "Blue", "Magenta"
    )
    
    $i = 0
    foreach ($line in $asciiArtLines) {
        # Cycle through colors and apply them to the text
        Write-Host -ForegroundColor $rainbowColors[$i % $rainbowColors.Length] $line
        $i++
    }
}


function Get-Flow {
    Clear-Host
    Show-RainbowAscii
    Write-Host "-----------------------------------------------------------------`n`n`n" -ForegroundColor Green


    Write-Host "1) Verificando Instalacao do TLauncher..."
    Start-Sleep 1
    if (-Not (Get-TLauncherInstallation)) {
        Install-TLauncher
    }
    else {
        Write-Host " - TLauncher encontrado." -ForegroundColor Green
    }

    Write-Host "2) Configurando o TLauncher..."
    Start-Sleep 1
    Update-TLauncher

    Write-Host "3) Verificando GIT..."
    Start-Sleep 1
    if (-Not (Get-GitInstallation)) {
        Install-Git
    }

    Write-Host "4) Verificando Repositorio Git..."
    Start-Sleep 1
    if (-Not (Get-GitRepo)) {
        New-GitRepo
    }

    Write-Host "5) Atualizando Repositorio Git..."
    Start-Sleep 1
    Update-GitRepo

    

    Start-Process -FilePath "$AppDataPath\TLauncher.exe"
}

function Clear-Installation {
    Send-Msg "Tem certeza que deseja remover os arquivos de instalacao? (y/n)" -Variant "Warning"
    $choice = Read-Host -Prompt "y/n"
    if($choice -eq "y") {
        if (Test-Path -Path $TLauncherPath) {
            Remove-Item -Path $TLauncherPath -Recurse -Force
        }
        if (Test-Path -Path $ModsFolder) {
            Remove-Item -Path $ModsFolder -Recurse -Force
        }
        if (Test-Path -Path $TLauncherPropertiesPath) {
            Remove-Item -Path $TLauncherPropertiesPath -Force
        }
        Send-Msg -Message "Instalacao limpa." -Variant "Success"
    } else {
        Send-Msg -Message "Operacao cancelada." -Variant "Error"
    }

    Show-Menu
    
}

function Show-Menu {
    Show-RainbowAscii
    Write-Host "-----------------------------------------------------------------`n`n`n" -ForegroundColor Green
    Write-Host "1) Jogar"
    Write-Host "2) Limpar Instalacao"
    Write-Host "3) Sair" 
    Write-Host "`n`n`n-----------------------------------------------------------------`n" -ForegroundColor Green
    $option = Read-Host -Prompt "Escolha uma opcao"
    switch ($option) {
        1 {
            Get-Flow
        }
        2 {
            Clear-Installation
        }
        default {
           exit 1
        }
    }
}

Clear-Host
Show-Menu


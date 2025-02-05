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
    }
    catch {
        Write-Host "Process '$ProcessName' not found or could not be terminated. $_" -ForegroundColor Red
    }
}

function Get-KeyInput {
    $key = [System.Console]::ReadKey($true)  
    return $key.Key
}

function Invoke-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [int]$Exit = $true
    )

    Write-Host $Message -ForegroundColor Red
    Write-Host "Pressione qualquer tecla para continuar ou X para sair" -ForegroundColor Red
    Get-KeyInput
    if ($Exit) {
        exit 1
    }
    else {
        Clear-Host
    }
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

function Get-JavaInstallation {
    try {
        java -version > $null 2>&1
        return $true
    }
    catch {
        return $false
    }
}

function Install-Java {
    $java_latest_executable_download_url = "https://javadl.sun.com/webapps/download/AutoDL?BundleId=107944"
    $java_latest_executable = "$env:TEMP\Java-64-bit.exe"

    if (-Not(Test-Path $java_latest_executable)) {
        Send-Msg -Message "Fazendo download do Java..." -Variant "Warning"
        Get-FileWithProgress -Url $java_latest_executable_download_url -OutFile $java_latest_executable
    }
    Send-Msg -Message "Atualizando Java..." -Variant "Success"
    Start-Process -FilePath $java_latest_executable -Wait

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Send-Msg -Message "Java Atualizado" -Variant "Success"
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

    if (-Not(Test-Path $git_latest_executable)) {
        Send-Msg -Message "Git nao instalado, fazendo download..." -Variant "Warning"
        Get-FileWithProgress -Url $git_latest_executable_download_url -OutFile $git_latest_executable
    }
    Send-Msg -Message "Atualizando Git..." -Variant "Success"
    Start-Process -FilePath $git_latest_executable -ArgumentList "/VERYSILENT", "/NORESTART" -Wait

    
    Start-Sleep -Seconds 5
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Send-Msg -Message "Git Atualizado" -Variant "Success"
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
    $Properties = Get-Content -Path $TLauncherPropertiesPath
    $UpdatedProperties = $Properties -replace 'login.version.game=.*', ''
    $UpdatedProperties += "login.version.game=Fabric 1.20.1"
    Set-Content -Path $TLauncherPropertiesPath -Value $UpdatedProperties
    Send-Msg -Message "Versao do Fabric corrigida" -Variant "Success"
    
    Send-Msg -Message "TLauncher configurado." -Variant "Success"
}

function Get-GitRepo {
    if (Test-Path -Path "$ModsFolder\.git") {
        Send-Msg -Message "Repositorio Git encontrado na pasta de mods." -Variant "Success"
        return $true
    }
    else {
        Send-Msg -Message "Nenhum repositorio Git encontrado na pasta de mods." -Variant "Warning"
    }
}

function New-GitRepo {
    Send-Msg -Message "Inicializando repositorio Git na pasta de mods..." -Variant "Warning"
    git init $ModsFolder > $null 2>&1
    Send-Msg -Message "Repositorio Git inicializado." -Variant "Success"
    Send-Msg -Message "Adicionando repositorio remoto..." -Variant "Warning"
    & git -C $ModsFolder remote add origin $GitRemoteRepo > $null 2>&1
    Send-Msg -Message "Repositório remoto adicionado." -Variant "Success"
}

function Update-GitRepo {
    Send-Msg -Message "Atualizando repositorio remoto..." -Variant "Warning"
    & git -C $ModsFolder fetch origin
    & git -C $ModsFolder reset --hard origin/master 
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


function Invoke-Launcher {
    
    
    Clear-Host
    Show-RainbowAscii
    Write-Host "-----------------------------------------------------------------`n`n`n" -ForegroundColor Green

    Write-Host "0) Verificando Instalacao do Java..."
    Start-Sleep 1
    try {
        if(-Not(Get-JavaInstallation)){
            Install-Java
        }
        else {
            Write-Host " - Java encontrado." -ForegroundColor Green
        }
    }
    catch {
        <#Do this if a terminating exception happens#>
    }

    Write-Host "1) Verificando Instalacao do TLauncher..."
    Start-Sleep 1
    try {
        if (-Not (Get-TLauncherInstallation)) {
            Install-TLauncher
        }
        else {
            Write-Host " - TLauncher encontrado." -ForegroundColor Green
        }
    }
    catch {
        Invoke-Error -Message "Falha ao verificar a instalacao do TLauncher. Erro: $_"
        return Show-Menu
    }

    Write-Host "2) Configurando o TLauncher..."
    Start-Sleep 1
    try {
        if (Test-Path -Path $TLauncherPropertiesPath) {
            Update-TLauncher
            
        }
        else {
            Invoke-Error -Message "Arquivo de propriedades do TLauncher nao encontrado. Por favor, tente reinstalar." -Exit $false
            return Show-Menu
        }
    }
    catch {
        Invoke-Error -Message "Falha ao configurar o TLauncher. Erro: $_"
        return Show-Menu
    }

    Write-Host "3) Verificando GIT..."
    Start-Sleep 1
    try {
        if (-Not (Get-GitInstallation)) {
            Install-Git 
        }
        else { 
            Send-Msg -Message "Git encontrado." -Variant "Success"
        }
    }
    catch {
        Invoke-Error -Message "Falha ao verificar instalacao do Git. Erro: $_"
        return Show-Menu
    }
    
    Write-Host "4) Verificando Pasta de Mods..."
    Start-Sleep 1
    try {
        if (-Not (Get-GitRepo)) {
            New-GitRepo
        }
        else {
            Send-Msg -Message "Repositorio Git encontrado." -Variant "Success"
        }
    }
    catch {
        Invoke-Error -Message "Falha ao inicializar o repositorio Git. Erro: $_"
        return Show-Menu
    }
    

    Write-Host "5) Atualizando Mods..."
    Start-Sleep 1
    try {
        Update-GitRepo
    }
    catch {
        Invoke-Error -Message "Falha ao atualizar os mods. Erro: $_"
        return Show-Menu
    }

    

    Start-Process -FilePath "$AppDataPath\TLauncher.exe"
    exit 0
}

function Clear-Installation {
    Send-Msg "Tem certeza que deseja remover os arquivos de instalacao? Isso removera todos os arquivos do TLauncher e da pasta de Mods" -Variant "Warning"
    Send-Msg "Pressione Y para confirmar ou qualquer outra tecla para cancelar" -Variant "Warning"
    $key = Get-KeyInput
    if ($key -eq "Y") {
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
    }
    else {
        Send-Msg -Message "Operacao cancelada." -Variant "Error"
    }

    
}

function Update-Mods {
    if (-Not (Get-GitInstallation)) {
        Install-Git 
    }
    else { 
        Send-Msg -Message "Git encontrado." -Variant "Success"
    }
    if (-Not (Get-TLauncherInstallation)) {
        return Send-Msg -Message "TLauncher nao encontrado. Por favor, instale o TLauncher antes de atualizar os mods." -Variant "Error"
    }
    if (-Not (Get-GitRepo)) {
        New-GitRepo
    }
    Update-GitRepo
}

function Show-Menu {
    Show-RainbowAscii
    Write-Host "-----------------------------------------------------------------`n`n`n" -ForegroundColor Green
    Write-Host "1) Jogar"
    Write-Host "2) Atualizar Mods"
    Write-Host "3) Limpar Instalacao"
    Write-Host "X) Sair" 
    Write-Host "`n`n`n-----------------------------------------------------------------`n" -ForegroundColor Green
    Write-Host "Versao 0.0.1" -ForegroundColor DarkYellow
    $key = Get-KeyInput  # Wait for a single key press
    switch ($key) {
        "D1" {
            Invoke-Launcher
        }
        "D2" {
            Update-Mods
        }
        "D3" {
            Clear-Installation
        }
        default {
            exit 1
        }
    }
    Show-Menu
}

Clear-Host
Show-Menu


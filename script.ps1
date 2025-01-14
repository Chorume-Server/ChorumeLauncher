# Variables
$OutputEncoding = [System.Text.Encoding]::UTF8
$AppDataPath = "$env:APPDATA\.minecraft"
$TLauncherPath = "$env:APPDATA\.tlauncher"
$TLauncherPropertiesPath = "$TLauncherPath\tlauncher-2.0.properties"
$ModsFolder = "$AppDataPath\mods"
$LocalChecksumFile = "$ModsFolder\checksum.txt"
$BucketAddress = "https://chorumeserver.s3.sa-east-1.amazonaws.com"
$ServerChecksumUrl = "$BucketAddress/checksum.txt"  # Replace with your actual URL
$PublicBucketBaseUrl = "$BucketAddress"   # Base URL for mods
$global:HasInstalledTLauncher = $false

# Function to download the server checksum file
Function Get-ServerChecksum {
    Write-Host "Downloading server checksum..."
    $ServerChecksumPath = "$ModsFolder\server_checksum.txt"
    Invoke-WebRequest -Uri $ServerChecksumUrl -OutFile $ServerChecksumPath -ErrorAction Stop
    Write-Host "Server checksum downloaded."
    return $ServerChecksumPath
}

# Function to compare checksums and return mismatched files
Function Compare-Checksums {
    param (
        [string]$LocalChecksum,
        [string]$ServerChecksum
    )
    Write-Host "Comparing checksums..."
    $LocalContent = Get-Content -Path $LocalChecksum -ErrorAction Stop
    $ServerContent = Get-Content -Path $ServerChecksum -ErrorAction Stop

    $LocalFiles = @{}
    foreach ($line in $LocalContent) {
        $parts = $line -split ' '
        $LocalFiles[$parts[1]] = $parts[0]
    }

    $ServerFiles = @{}
    foreach ($line in $ServerContent) {
        $parts = $line -split ' '
        $ServerFiles[$parts[1]] = $parts[0]
    }

    $MismatchedFiles = @()
    foreach ($file in $ServerFiles.Keys) {
        if ($file -notlike "*/" -and (-Not $LocalFiles.ContainsKey($file) -or $LocalFiles[$file] -ne $ServerFiles[$file])) {
            $MismatchedFiles += $file
        }
    }

    if ($MismatchedFiles.Count -eq 0) {
        Write-Host "All files are up-to-date." -ForegroundColor Green
    }
    else {
        Write-Host "Mismatched or missing files detected:" -ForegroundColor Yellow
        $MismatchedFiles | ForEach-Object { Write-Host "- $_" }
    }

    return $MismatchedFiles
}

# Function to start the Minecraft launcher
Function Start-MinecraftLauncher {
    # Attempt to locate Minecraft.exe in the default directory
    $MinecraftExe = "$AppDataPath\Microsoft\VisualStudio\Packages\Minecraft\MinecraftLauncher.exe"
    if (-Not (Test-Path -Path $MinecraftExe)) {
        # If not found, prompt user to input the Minecraft launcher path
        $MinecraftExe = Write-Host "Minecraft executable not found. Please enter the path to MinecraftLauncher.exe"
    }

    # Check if the user-provided path exists
    if (Test-Path -Path $MinecraftExe) {
        Write-Host "Launching Minecraft..."
        Start-Process -FilePath $MinecraftExe
    }
    else {
        Write-Host "Invalid Minecraft executable path. Exiting." -ForegroundColor Red
        <# exit 1 #>
    }
}

# Function to save user directory for future use
Function Save-UserDirectory {
    param (
        [string]$DirectoryPath
    )
    $ConfigPath = "$AppDataPath\minecraft_launcher_config.txt"
    Set-Content -Path $ConfigPath -Value $DirectoryPath
}

# Function to load the saved user directory
Function Start-UserDirectory {
    $ConfigPath = "$AppDataPath\minecraft_launcher_config.txt"
    if (Test-Path -Path $ConfigPath) {
        return Get-Content -Path $ConfigPath
    }
    return $null
}

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
        Write-Host -NoNewline "$progress $percentComplete% completo`n"

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

function Install-JavaIfNeeded {
    # Check if Java is installed
    try {
        $javaVersion = & java -version | Out-Null
        Write-Host "Java esta instalado!" -ForegroundColor Green
        return
    }
    catch {
        Write-Host "Java nao esta instalado, baixando instalador..."
    }

    # Define the Java installer URL and path
    $JavaInstallerPath = "$env:TEMP\jdk-23_windows-x64_bin.exe"
    $JavaInstallerUrl = "https://download.oracle.com/java/23/latest/jdk-23_windows-x64_bin.exe"  # Update with the correct URL for your Java version

    # Download the Java installer
    Write-Host "Baixando instalador do Java $JavaVersion..."
    Get-FileWithProgress -Url $JavaInstallerUrl -OutFile $JavaInstallerPath

    # Run the installer
    Write-Host "Instalando Java $JavaVersion..."
    Start-Process -FilePath $JavaInstallerPath -ArgumentList "/s" -Wait

    # Verify installation
    try {
        $javaVersion = & java -version
        Write-Host "Java $JavaVersion instalado com sucesso."
    }
    catch {
        Write-Host "Instalacao do Java falhou. Erro: $_" -ForegroundColor Red
    }
}

function Install-TLauncher {
    Write-Host " - Pasta .minecraft nao encontrada. Baixando o TLauncher."
    $TLauncherInstallerPath = "$env:TEMP\TLauncher-Installer-1.6.0.exe"
    if (Test-Path $TLauncherInstallerPath) {
        Write-Host " - TLauncher ja baixado. Executando o instalador..." -ForegroundColor Green
        Write-Host " - VOCE SERA REDIRECIONADO A INSTALACAO. NO FIM, MARQUE A OPCAO DE INICIAR O LAUNCHER, CASO CONTRARIO NAO IRA FUNCIONAR" -ForegroundColor Red
        Write-Host "PRESSIONE ENTER PARA CONTINUAR" -ForegroundColor Red
        Read-Host
        Write-Host " - Aguardando instalacao do TLauncher..." -ForegroundColor Yellow
        Start-Process -FilePath $TLauncherInstallerPath
        Watch-ProcessRunningAndStopping -ProcessName "TLauncher-Installer-1.6.0"
    }
    else {
        try {
            Get-FileWithProgress -Url "https://dl2.tlauncher.org/f.php?f=files%2FTLauncher-Installer-1.6.0.exe" -OutFile $TLauncherInstallerPath
            Write-Host " - Baixado $FileSize bytes de $OutFile"
            Write-Host " - TLauncher baixado com sucesso. Executando o instalador" -ForegroundColor Green
            Write-Host " - VOCE SERA REDIRECIONADO A INSTALACAO. NO FIM, MARQUE A OPCAO DE INICIAR O LAUNCHER, CASO CONTRARIO NAO IRA FUNCIONAR" -ForegroundColor Red
            Write-Host "PRESSIONE ENTER PARA CONTINUAR" -ForegroundColor Red
            Read-Host
            Start-Process -FilePath $TLauncherInstallerPath
            Watch-ProcessRunningAndStopping -ProcessName "TLauncher-Installer-1.6.0"
            
        }
        catch {
            Write-Host " - Falha ao baixar o TLauncher. Erro: $_" -ForegroundColor Red
            <# exit 1 #>
        }
    }
    $LauncherProccessName = "java"
    $UpdaterProcessName = "javaw"
    Write-Host " - Aguardando atualizacao do TLauncher..." -ForegroundColor Yellow
    Watch-ProcessRunningAndStopping -ProcessName $UpdaterProcessName
    Write-Host " - Aguardando inicializacao do TLauncher..." -ForegroundColor Yellow
    while ((Get-ProcessRunning -ProcessName $UpdaterProcessName) -and (Get-ProcessRunning -ProcessName $LauncherProccessName)) {
        Start-Sleep -Seconds 2
    }
    Stop-ProcessByName -ProcessName $LauncherProccessName
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

# Display the rainbow-colored ASCII art


function Get-Flow {
    Clear-Host
    Show-RainbowAscii
    Write-Host "-----------------------------------------------------------------`n`n`n" -ForegroundColor Green

    Write-Host "1) Verificando instalacao do Java.."
    Start-Sleep 1
    Install-JavaIfNeeded


    Write-Host "2) Verificando Instalacao do TLauncher..."
    Start-Sleep 1
    if (-Not (Test-Path -Path $TLauncherPath)) {
        Install-TLauncher
    }
    else {
        Write-Host " - Minecraft encontrado." -ForegroundColor Green
    }

    Write-Host "3) Configurando o TLauncher..."
    Start-Sleep 1
    if ((Test-Path -Path $TLauncherPath)) {
        if (Test-Path -Path $TLauncherPropertiesPath) {
            $Properties = Get-Content -Path $TLauncherPropertiesPath
            $UpdatedProperties = $Properties -replace 'login.version.game=.*', ''
            $UpdatedProperties += "login.version.game=ForgeOptiFine 1.20.1"
            Set-Content -Path $TLauncherPropertiesPath -Value $UpdatedProperties
            Write-Host " - Versao do Forge corrigida" -ForegroundColor Green
        }
        else {
            Write-Host " - tlauncher-2.0.properties file not found." -ForegroundColor Red
        }
        Write-Host " - TLauncher inicializado. Iniciando o Minecraft pelo TLauncher..." -ForegroundColor Green
        
    }

    Write-Host "3) Verificando pasta de mods..."
    Start-Sleep 1
    if (-Not (Test-Path -Path $ModsFolder)) {
        Write-Host "Pasta de mods nao encontrada. Criando..." -ForegroundColor Yellow
        New-Item -Path $ModsFolder -ItemType Directory
    }
    else {
        Write-Host "Pasta de mods encontrada." -ForegroundColor Green
    }

    Write-Host "5) Verificando checksums..."
    if (Test-Path $LocalChecksumFile) {
        Remove-Item $LocalChecksumFile -Force
    }

    # Criar um novo arquivo de checksum
    New-Item -Path $LocalChecksumFile -ItemType File -Force
    Write-Host "Arquivo de checksum criado."
    $Properties = Get-Content -Path $LocalChecksumFile
    $UpdatedProperties = $Properties

    

    # Get all .jar files in the ModsFolder
    $jarFiles = Get-ChildItem -Path $ModsFolder -Filter *.jar
    $UpdatedProperties = ""

    # Process each file using a for loop
    for ($i = 0; $i -lt $jarFiles.Count; $i++) {
        $file = $jarFiles[$i]
        $filePath = $file.FullName
        $relativePath = $filePath.Substring($ModsFolder.Length).TrimStart("\")
        Write-Host "Processing file: '$relativePath'"

        try {
            # Calculate the MD5 hash
            $hash = (Get-FileHash -Path $filePath -Algorithm MD5).Hash
            Write-Host "Hash calculated: $hash"

            $lowerCaseHash = $hash.ToLower()

            # Check if it's the last file
            if ($i -eq $jarFiles.Count - 1) {
                # Last item: do not append a newline
                $UpdatedProperties += "$lowerCaseHash mods/$($file.Name)"
            }
            else {
                # Append with a newline
                $UpdatedProperties += "$lowerCaseHash mods/$($file.Name)`n"
            }
        }
        catch {
            Write-Host "Error processing file: $relativePath"
            Write-Host "Error details: $_"
        }
    }

    # Write the final content to the checksum file
    if($UpdatedProperties -ne ""){
        Set-Content -Path $LocalChecksumFile -Value $UpdatedProperties
    }
    else{
        Write-Host "Nenhum arquivo de mod encontrado." -ForegroundColor Yellow
    }
    Write-Host "Processamento concluído."
    
    $ServerChecksumPath = Get-ServerChecksum
    $MismatchedFiles = Compare-Checksums -LocalChecksum $LocalChecksumFile -ServerChecksum $ServerChecksumPath

    if ($MismatchedFiles.Count -gt 0) {
        Write-Host " - Baixando arquivos de mods..." -ForegroundColor Yellow
        foreach ($file in $MismatchedFiles) {
            $parsedFileName = $file.Replace(" ", "+")
            $ModUrl = "$PublicBucketBaseUrl/$parsedFileName"
            $ModPath = "$AppDataPath\$parsedFileName"
            try {
                Write-Host "Baixando mod '$ModUrl'..." -ForegroundColor Yellow
                Get-FileWithProgress -Url $ModUrl -OutFile $ModPath
            }
            catch {
                Write-Host "Erro ao baixar mod '$file'. Error: $_" -ForegroundColor Red
            }
        }
        Write-Host "Arquivos de mods baixados com sucesso." -ForegroundColor Green
    }



    Start-Process -FilePath "$AppDataPath\TLauncher.exe"
}

Get-Flow



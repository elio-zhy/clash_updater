function Confirm-AdminPrivilege {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()

    (New-object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Confirm-PowershellVersion {
    $version = $PSVersionTable.PSVersion.Major
    Write-Host "Checking Windows Powershell version -- $version" -ForegroundColor Green
    if ($version -le 2) {
        Write-Host "Using Windows Powershell $version is unsupported. Upgrade your Windows Powershell." -ForegroundColor Red
        throw
    }
}

function Get-LocalClashPath {
    return [System.IO.Path]::Combine((Get-Location).Path, "Clash for Windows.exe")
}

function Confirm-ClashExistance($filePath) {
    return Test-Path $filePath
}

function Get-Arch($filePath) {
    # Reference: http://superuser.com/a/891443
    $result = ""
    [int32]$MACHINE_OFFSET = 4
    [int32]$PE_POINTER_OFFSET = 60

    [byte[]]$data = New-Object -TypeName System.Byte[] -ArgumentList 4096
    $stream = New-Object -TypeName System.IO.FileStream -ArgumentList ($filePath, "Open", "Read")
    $stream.Read($data, 0, 4096) | Out-Null

    # DOS header is 64 bytes, last element, long (4 bytes) is the address of the PE header
    [int32]$PE_HEADER_ADDR = [System.BitConverter]::ToInt32($data, $PE_POINTER_OFFSET)
    [int32]$machineUint = [System.BitConverter]::ToUInt16($data, $PE_HEADER_ADDR + $MACHINE_OFFSET)

    switch ($machineUint) {
        0 { $result = "Native" }
        0x014c { $result = "i686" } # 32bit
        0x0200 { $result = 'Itanium' }
        0x8664 { $result = "x86_64" } # 64bit
    }

    return $result
}

function Get-LatestMetadata($arch) {
    $fileName = ""
    $downloadLink = ""
    $pattern = ""
    $remoteVersion = ""

    $api = "https://api.github.com/repos/Fndroid/clash_for_windows_pkg/releases/latest"
    $json = Invoke-WebRequest -Proxy $proxy $api -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing | ConvertFrom-Json

    switch ($arch) {
        "i686" {
            $pattern = "Clash\.for\.Windows-(\d*\.\d*.\d*)-ia32-win.7z"

            $fileName = $json.assets | Where-Object { $_.name -match $pattern } | Select-Object -ExpandProperty name
            $downloadLink = $json.assets | Where-Object { $_.name -match "Clash\.for\.Windows-\d*\.\d*.\d*-ia32-win.7z" } | Select-Object -ExpandProperty browser_download_url
        }
        "x86_64" {
            $pattern = "Clash\.for\.Windows-(\d*\.\d*.\d*)-win.7z"

            $fileName = $json.assets | Where-Object { $_.name -match $pattern } | Select-Object -ExpandProperty name
            $downloadLink = $json.assets | Where-Object { $_.name -match $pattern } | Select-Object -ExpandProperty browser_download_url
        }
    }

    $_ = $fileName -match $pattern
    $remoteVersion = $Matches[1]

    return $fileName, $downloadLink, $remoteVersion
}

function Get-LocalVersion($filePath) {
    $version = (Get-Item $filePath).VersionInfo.FileVersion

    return $version
}

function Read-KeyOrTimeout($prompt, $key) {
    $seconds = 9
    $startTime = Get-Date
    $timeOut = New-TimeSpan -Seconds $seconds

    Write-Host "$prompt" -ForegroundColor Green

    # Basic progress bar
    [System.Console]::CursorLeft = 0
    [System.Console]::Write("[")
    [System.Console]::CursorLeft = $seconds + 2
    [System.Console]::Write("]")
    [System.Console]::CursorLeft = 1

    while (-not [System.Console]::KeyAvailable) {
        $currentTime = Get-Date
        Start-Sleep -s 1
        Write-Host "#" -ForegroundColor Green -NoNewline
        if ($currentTime -gt $startTime + $timeOut) {
            Break
        }
    }

    if ([System.Console]::KeyAvailable) {
        $response = [System.Console]::ReadKey($true).Key
    }
    else {
        $response = $key
    }

    return $response.ToString()
}

function Get-Latest-Clash($remoteName, $downloadLink) {
    Write-Host "Downloading $filename" -ForegroundColor Green
    $global:ProgressPreference = "Continue"
    Invoke-WebRequest -Proxy $proxy -Uri $downloadLink -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox -OutFile $remoteName
}

function Get-7zPath {
    $result = ""

    $result = [System.Environment]::ExpandEnvironmentVariables("%Programs%\7-zip\7z.exe")

    if (-not (Test-Path $result)) {
        Write-Host "7z not installed. Please install manually" -ForegroundColor Red
        throw
    }

    return $result
}

function Stop-Clash {
    $clash = Get-Process "Clash for Windows" -ErrorAction SilentlyContinue

    if ($clash) {
        $result = Read-KeyOrTimeout "Clash is running, close? [Y/N] (default=N)" "N"
        Write-Host ""

        if ($result -eq "Y") {
            $clash | Stop-Process -Force
        }
        else {
            Write-Host "Please close clash manually and restart update script." -ForegroundColor Red
            throw
        }
    }
}

function Start-Extraction($fileName, $7zPath) {
    & 7zPath x -y $fileName | FIND "Extracting archive" | Write-Host -ForegroundColor Green
}

function Confirm-AutoDelete($archive) {
    $autodelete = ""
    $file = "settings.xml"

    if (-not (Test-Path $file)) {
        New-XML
    }
    [xml]$doc = Get-Content $file

    if ($doc.settings.autodelete -eq "unset") {
        $result = Read-KeyOrTimeout "Delete clash archive after extract? [Y/N] (default=Y)" "Y"
        Write-Host ""

        if ($result -eq "Y") {
            $autodelete = "true"
        }
        else {
            $autodelete = "false"
        }
        $doc.settings.autodelete = $autodelete
        $doc.Save($file)
    }

    if ($doc.settings.autodelete -eq "true") {
        if (Test-Path $archive) {
            Remove-Item -Force $archive
        }
    }
}

function New-XML {
    @"
<settings>
  <autodelete>unset</autodelete>
</settings>
"@ | Set-Content "settings.xml" -Encoding UTF8
}

function Update-Clash {
    $localFilePath = ""
    $remoteName = ""
    $downloadLink = ""
    $arch = ""
    $needDownload = $false
    $7zPath = ""

    $localFilePath = Get-LocalClashPath

    if (Confirm-ClashExistance $localFilePath) {
        $arch = Get-Arch $localFilePath
        $remoteName, $downloadLink, $remoteVersion = Get-LatestMetadata $arch
        $localVersion = Get-LocalVersion $localfilePath

        if ($localVersion -match $remoteVersion) {
            Write-Host "You are already using latest clash build -- $remoteVersion" -ForegroundColor Green
            $needDownload = $false
        }
        else {
            Write-Host "Newer clash build availabel -- $remoteVersion" -ForegroundColor Green
            $needDownload = $true
        }
    }
    else {
        Write-Host "clash doesn't exist." -ForegroundColor Green -NoNewline
        $result = Read-KeyOrTimeout "Proceed with downloading? [Y/N] (default=Y)" "Y"
        Write-Host ""

        if ($result -eq "Y") {
            $needDownload = $true
            if (Test (Join-Path $env:windir "SysWow64")) {
                Write-Host "Detecting System Type is 64-bit" -ForegroundColor Green
                $arch = "x86_64"
            }
            else {
                Write-Host "Detecting System Type is 32-bit" -ForegroundColor Green
                $arch = "i686"
            }
            $remoteName, $downloadLink, $remoteVersion = Get-LatestMetadata $arch
        }
        else {
            $needDownload = $false
        }
    }

    if ($needDownload) {
        Get-Latest-Clash $remoteName $downloadLink
        $7zPath = Get-7zPath
        Stop-Clash
        Start-Extraction $remoteName $7zPath
        Write-Host "Update done. Restart clash manually." -ForegroundColor Green
    }

    Confirm-AutoDelete $remoteName
}

#
# Main entry point
#
if (Confirm-AdminPrivilege) {
    Write-Host "Running script with administrator privileges" -ForegroundColor Yellow
}
else {
    Write-Host "Running script without administrator privileges" -ForegroundColor Red
}

try {
    Confirm-PowershellVersion
    Update-Clash
}
catch [System.Exception] {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
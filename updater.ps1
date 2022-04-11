$proxy = "http://127.0.0.1:1080"

function Check-7z {
    $7zdir = (Get-Location).Path + "\7z"
    if (-not (Test-Path ($7zdir + "\7za.exe")) -and -not (Test-Path (Get-Command "7z.exe").Path))
    {
        $download_file = (Get-Location).Path + "\7z.zip"
        Write-Host "Downloading 7z" -ForegroundColor Green
        Invoke-WebRequest -Proxy $proxy -Uri "https://download.sourceforge.net/sevenzip/7za920.zip" -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox -OutFile $download_file
        Write-Host "Extracting 7z" -ForegroundColor Green
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($download_file, $7zdir)
        Remove-Item -Force $download_file
    }
    else
    {
        Write-Host "7z already exist. Skipped download" -ForegroundColor Green
    }
}

function Check-PowershellVersion {
    $version = $PSVersionTable.PSVersion.Major
    Write-Host "Checking Windows PowerShell version -- $version" -ForegroundColor Green
    if ($version -le 2)
    {
        Write-Host "Using Windows PowerShell $version is unsupported. Upgrade your Windows PowerShell." -ForegroundColor Red
        throw
    }
}

function Check-Clash {
    $clash = (Get-Location).Path + "\Clash for Windows.exe"
    $is_exist = Test-Path $clash
    return $is_exist
}

function Download-Clash ($filename, $link) {
    Write-Host "Downloading" $filename -ForegroundColor Green
    $global:progressPreference = 'Continue'
    Invoke-WebRequest -Proxy $proxy -Uri $link -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox -OutFile $filename
}

function Extract-Clash ($file) {
    if (Test-Path (Get-Command "7z.exe").Path) {
        & ((Get-Command "7z.exe").Path) x -y $file | FIND "Extracting archive" | Write-Host -ForegroundColor Green
    }
    else {
        $7za = (Get-Location).Path + "\7z\7za.exe"
        Write-Host "Extracting" $file -ForegroundColor Green
        & $7za x -y $file
    }
}

function Get-Latest-Clash($Arch) {
    $filename = ""
    $download_link = ""
    
    $api_gh = "https://api.github.com/repos/Fndroid/clash_for_windows_pkg/releases/latest"
    $json = Invoke-WebRequest -Proxy $proxy $api_gh -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing | ConvertFrom-Json
    switch ($Arch)
    {
        "i686" {
            $filename = $json.assets | where { $_.name -Match "Clash\.for\.Windows-\d*\.\d*.\d*-ia32-win.7z" } | Select-Object -ExpandProperty name
            $download_link = $json.assets | where { $_.name -Match "Clash\.for\.Windows-\d*\.\d*.\d*-ia32-win.7z" } | Select-Object -ExpandProperty browser_download_url
        }
        "x86_64" {
            $filename = $json.assets | where { $_.name -Match "Clash\.for\.Windows-\d*\.\d*.\d*-win.7z" } | Select-Object -ExpandProperty name
            $download_link = $json.assets | where { $_.name -Match "Clash\.for\.Windows-\d*\.\d*.\d*-win.7z" } | Select-Object -ExpandProperty browser_download_url
        }
    }
    
    return $filename, $download_link
}

function Get-Arch {
    # Reference: http://superuser.com/a/891443
    $FilePath = [System.IO.Path]::Combine((Get-Location).Path, 'Clash for Windows.exe')
    [int32]$MACHINE_OFFSET = 4
    [int32]$PE_POINTER_OFFSET = 60

    [byte[]]$data = New-Object -TypeName System.Byte[] -ArgumentList 4096
    $stream = New-Object -TypeName System.IO.FileStream -ArgumentList ($FilePath, 'Open', 'Read')
    $stream.Read($data, 0, 4096) | Out-Null

    # DOS header is 64 bytes, last element, long (4 bytes) is the address of the PE header
    [int32]$PE_HEADER_ADDR = [System.BitConverter]::ToInt32($data, $PE_POINTER_OFFSET)
    [int32]$machineUint = [System.BitConverter]::ToUInt16($data, $PE_HEADER_ADDR + $MACHINE_OFFSET)

    $result = "" | select FilePath, FileType
    $result.FilePath = $FilePath

    switch ($machineUint)
    {
        0      { $result.FileType = 'Native' }
        0x014c { $result.FileType = 'i686' } # 32bit
        0x0200 { $result.FileType = 'Itanium' }
        0x8664 { $result.FileType = 'x86_64' } # 64bit
    }

    $result
}

function ExtractVersionFromFile {
    $version = (Get-Item "Clash for Windows.exe").VersionInfo.FileVersion
    return $version
}

function ExtractVersionFromURL($filename) {
    $pattern = "Clash\.for\.Windows-(\d*\.\d*\.\d*)-(.*?)\.7z"
    $bool = $filename -match $pattern
    return $matches[1]
}

function Test-Admin
{
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Create-XML {
@"
<settings>
  <autorestart>unset</autorestart>
  <autodelete>unset</autodelete>
</settings>
"@ | Set-Content "settings.xml" -Encoding UTF8
}

function Check-Autodelete($archive) {
    $autodelete = ""
    $file = "settings.xml"

    if (-not (Test-Path $file)) { Create-XML }
    [xml]$doc = Get-Content $file

    if ($doc.settings.autodelete -eq "unset") {
        $result = Read-KeyOrTimeout "Delete clash archives after extract? [Y/n] (default=Y)" "Y"
        Write-Host ""
        if ($result -eq 'Y') {
            $autodelete = "true"
        }
        elseif ($result -eq 'N') {
            $autodelete = "false"
        }
        $doc.settings.autodelete = $autodelete
        $doc.Save($file)
    }

    if ($doc.settings.autodelete -eq "true") {
        if (Test-Path $archive)
        {
            Remove-Item -Force $archive
        }
    }
}

function Shutdown-Clash {
    $name = "Clash for Windows"
    Stop-Process -Name $name
}

function Check-Autorestart {
    $autorestart = ""
    $file = "settings.xml"
    $filepath = (Get-Location).Path + "\Clash for Windows.exe"

    if (-not (Test-Path $file)) { Create-XML }
    [xml]$doc = Get-Content $file

    if ($doc.settings.autorestart -eq "unset") {
        $result = Read-KeyOrTimeout "Restart clash process after extract? [Y/n] (default=Y)" "Y"
        Write-Host ""
        if ($result -eq 'Y') {
            $autorestart = "true"
        }
        elseif ($result -eq 'N') {
            $autorestart = "false"
        }
        $doc.settings.autorestart = $autorestart
        $doc.Save($file)
    }

    if ($doc.settings.autorestart -eq "true") {
        if (Test-Path $filepath) {
            $command = Start-Job -ScriptBlock { Start-Process -FilePath $args[0] } -ArgumentList $filepath
        }
    }
}

function Upgrade-Clash {
    $need_download = $false
    $remoteName = ""
    $download_link = ""
    $arch = ""

    if (Check-Clash) {
        $arch = (Get-Arch).FileType
        $remoteName, $download_link = Get-Latest-Clash $arch
        $localversion = ExtractVersionFromFile
        $remoteversion = ExtractVersionFromURL $remoteName
        if ($localversion -match $remoteversion)
        {
            Write-Host "You are already using latest clash build -- $remoteName" -ForegroundColor Green
            $need_download = $false
        }
        else {
            Write-Host "Newer clash build available" -ForegroundColor Green
            $need_download = $true
        }
    }
    else {
        Write-Host "clash doesn't exist. " -ForegroundColor Green -NoNewline
        $result = Read-KeyOrTimeout "Proceed with downloading? [Y/n] (default=y)" "Y"
        Write-Host ""

        if ($result -eq "Y") {
            $need_download = $true
            if (Test-Path (Join-Path $env:windir "SysWow64")) {
                Write-Host "Detecting System Type is 64-bit" -ForegroundColor Green
                $arch = "x86_64"
            }
            else {
                Write-Host "Detecting System Type is 32-bit" -ForegroundColor Green
                $arch = "i686"
            }
            $remoteName, $download_link = Get-Latest-Clash $arch
        }
        else {
            $need_download = $false
        }
    }

    if ($need_download) {
        Download-Clash $remoteName $download_link
        Check-7z
        Shutdown-Clash
        Extract-Clash $remoteName
        Check-Autorestart
    }
    Check-Autodelete $remoteName
}

function Read-KeyOrTimeout ($prompt, $key){
    $seconds = 9
    $startTime = Get-Date
    $timeOut = New-TimeSpan -Seconds $seconds

    Write-Host "$prompt " -ForegroundColor Green

    # Basic progress bar
    [Console]::CursorLeft = 0
    [Console]::Write("[")
    [Console]::CursorLeft = $seconds + 2
    [Console]::Write("]")
    [Console]::CursorLeft = 1

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

#
# Main script entry point
#
if (Test-Admin) {
    Write-Host "Running script with administrator privileges" -ForegroundColor Yellow
}
else {
    Write-Host "Running script without administrator privileges" -ForegroundColor Red
}

try {
    Check-PowershellVersion
    # Sourceforge only support TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Upgrade-Clash
    Write-Host "Operation completed" -ForegroundColor Magenta
}
catch [System.Exception] {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

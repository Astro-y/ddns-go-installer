[CmdletBinding()]
param(
    [ValidateSet("", "install", "update", "uninstall", "status", "list")]
    [string]$Command = "",
    [string]$Version = "",
    [int]$Port = 9876,
    [string]$Ip = "",
    [string]$Listen = "",
    [int]$Interval = 300,
    [string]$Config = "",
    [string]$Asset = "",
    [string]$InstallDir = "C:\Program Files\ddns-go"
)

$ErrorActionPreference = "Stop"

$Repo = "jeessy2/ddns-go"
$SupportedTargets = @(
    "android_arm64",
    "darwin_arm64",
    "darwin_x86_64",
    "freebsd_arm64",
    "freebsd_armv5",
    "freebsd_armv6",
    "freebsd_armv7",
    "freebsd_i386",
    "freebsd_x86_64",
    "linux_arm64",
    "linux_armv5",
    "linux_armv6",
    "linux_armv7",
    "linux_i386",
    "linux_mips64le_hardfloat",
    "linux_mips64le_softfloat",
    "linux_mips64_hardfloat",
    "linux_mips64_softfloat",
    "linux_mipsle_hardfloat",
    "linux_mipsle_softfloat",
    "linux_mips_hardfloat",
    "linux_mips_softfloat",
    "linux_riscv64",
    "linux_x86_64",
    "windows_arm64",
    "windows_i386",
    "windows_x86_64"
)

function Get-VersionWithoutPrefix {
    param([string]$Value)
    return $Value.TrimStart("v")
}

function Get-ListenAddress {
    if (-not [string]::IsNullOrWhiteSpace($Listen)) {
        return $Listen
    }
    if (-not [string]::IsNullOrWhiteSpace($Ip)) {
        return "${Ip}:$Port"
    }
    return ":$Port"
}

function Get-EffectivePort {
    $listenAddress = Get-ListenAddress
    if ($listenAddress -match ":(\d+)\]?$") {
        return [int]$Matches[1]
    }
    return $Port
}

function Get-LanIp {
    try {
        $addresses = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up } |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object {
                $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not [System.Net.IPAddress]::IsLoopback($_.Address) -and
                -not $_.Address.ToString().StartsWith("169.254.")
            } |
            ForEach-Object { $_.Address.ToString() }
        return @($addresses | Select-Object -First 1)[0]
    } catch {
        return $null
    }
}

function Get-LanUrl {
    $ip = Get-LanIp
    if ([string]::IsNullOrWhiteSpace($ip)) {
        return $null
    }
    $effectivePort = Get-EffectivePort
    return "http://${ip}:$effectivePort"
}

function Write-AccessUrls {
    Write-Host "Open: $(Get-WebUrl)"
    $lanUrl = Get-LanUrl
    if (-not [string]::IsNullOrWhiteSpace($lanUrl)) {
        Write-Host "      $lanUrl"
    }
}
function Get-PublicIp {
    $services = @(
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://ipinfo.io/ip"
    )
    foreach ($service in $services) {
        try {
            $ip = (Invoke-WebRequest -Uri $service -UseBasicParsing -TimeoutSec 5 -Headers @{ "User-Agent" = "ddns-go-installer" }).Content.Trim()
            if ($ip -match "^\d{1,3}(\.\d{1,3}){3}$") {
                return $ip
            }
        } catch {
            continue
        }
    }
    return $null
}

function Get-WebUrl {
    $listenAddress = Get-ListenAddress
    $effectivePort = Get-EffectivePort

    if ($listenAddress.StartsWith(":")) {
        $publicIp = Get-PublicIp
        if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
            return "http://${publicIp}:$effectivePort"
        }
        return "http://<server-ip>:$effectivePort"
    }
    if ($listenAddress.StartsWith("0.0.0.0:")) {
        $publicIp = Get-PublicIp
        if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
            return "http://${publicIp}:$effectivePort"
        }
        return "http://<server-ip>:$effectivePort"
    }
    $hostPart = ($listenAddress -replace ":\d+$", "").Trim("[", "]")
    if ($hostPart -eq "::") {
        $publicIp = Get-PublicIp
        if (-not [string]::IsNullOrWhiteSpace($publicIp)) {
            return "http://${publicIp}:$effectivePort"
        }
        return "http://<server-ip>:$effectivePort"
    }
    if ([string]::IsNullOrWhiteSpace($hostPart)) {
        $hostPart = "localhost"
    }
    return "http://${hostPart}:$effectivePort"
}

function Get-AssetName {
    param(
        [string]$VersionNoPrefix,
        [string]$Target
    )
    $extension = if ($Target.StartsWith("windows_")) { "zip" } else { "tar.gz" }
    return "ddns-go_$VersionNoPrefix`_$Target.$extension"
}

function Get-TargetFromAsset {
    param(
        [string]$AssetName,
        [string]$VersionNoPrefix
    )
    $target = $AssetName -replace "^ddns-go_$([regex]::Escape($VersionNoPrefix))_", ""
    $target = $target -replace "\.tar\.gz$", ""
    $target = $target -replace "\.zip$", ""
    return $target
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestVersion {
    $headers = @{ "User-Agent" = "ddns-go-installer" }
    $response = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" -Headers $headers -MaximumRedirection 5
    $finalUri = $response.BaseResponse.ResponseUri.AbsoluteUri
    $tag = ($finalUri.TrimEnd("/") -split "/")[-1]
    if ($tag -match "^v?\d+\.\d+\.\d+") {
        return $tag
    }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    if ($release.tag_name -match "^v?\d+\.\d+\.\d+") {
        return $release.tag_name
    }
    throw "GitHub latest returned an invalid version: $($release.tag_name)"
}

function Test-VersionValue {
    param([string]$Value)
    return $Value -match "^v?\d+\.\d+\.\d+"
}

function Get-RecentVersions {
    $headers = @{ "User-Agent" = "ddns-go-installer"; "Accept" = "application/vnd.github+json" }
    $response = Invoke-WebRequest -Uri "https://api.github.com/repos/$Repo/releases?per_page=5" -Headers $headers
    $releases = $response.Content | ConvertFrom-Json
    return @($releases | ForEach-Object { $_.tag_name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Resolve-Version {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        if (-not (Test-VersionValue -Value $Version)) {
            throw "Invalid version: $Version. Expected format: v6.17.1"
        }
        return $Version
    }

    $latest = Get-LatestVersion
    $versions = @()
    try {
        $versions = @(Get-RecentVersions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
        $versions = @()
    }
    if ($versions -notcontains $latest) {
        $versions = @($latest) + $versions
    }
    $options = @($versions | Select-Object -First 5) + @("Manual input version")
    $selected = Select-FromList "Select ddns-go version (Up/Down, Enter)" $options
    if ($selected -eq "Manual input version") {
        $answer = Read-Host "Input version, for example v6.17.1"
        if (-not (Test-VersionValue -Value $answer)) {
            throw "Invalid version: $answer. Expected format: v6.17.1"
        }
        return $answer
    }
    return $selected
}

function Get-DetectedTarget {
    $os = "windows"
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        "x64" { $normalized = "x86_64" }
        "x86" { $normalized = "i386" }
        "arm64" { $normalized = "arm64" }
        default { throw "Unsupported Windows architecture: $arch" }
    }
    $target = "$os`_$normalized"
    if ($SupportedTargets -notcontains $target) {
        throw "Unsupported target: $target"
    }
    return [pscustomobject]@{
        OS = $os
        Architecture = $normalized
        Target = $target
    }
}

function Select-FromList {
    param(
        [string]$Title,
        [string[]]$Items
    )
    if ($Items.Count -eq 0) {
        throw "No options available for $Title"
    }
    if ([Console]::IsInputRedirected) {
        return $Items[0]
    }

    $selected = 0
    $left = [Console]::CursorLeft
    $top = [Console]::CursorTop
    $width = [Math]::Max(40, [Console]::WindowWidth - 1)

    while ($true) {
        [Console]::SetCursorPosition($left, $top)
        Write-Host ($Title.PadRight($width))
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $line = if ($i -eq $selected) { "> $($Items[$i])" } else { "  $($Items[$i])" }
            if ($i -eq $selected) {
                Write-Host $line.PadRight($width) -ForegroundColor Black -BackgroundColor Gray
            } else {
                Write-Host $line.PadRight($width)
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
            "DownArrow" { $selected = ($selected + 1) % $Items.Count }
            "Enter" {
                Write-Host ""
                return $Items[$selected]
            }
        }
    }
}

function Select-ManualTarget {
    $os = Select-FromList "Select OS" @("android", "darwin", "freebsd", "linux", "windows")
    switch ($os) {
        "android" {
            return "android_arm64"
        }
        "darwin" {
            $arch = Select-FromList "Select macOS architecture" @("arm64", "x86_64")
            return "darwin_$arch"
        }
        "freebsd" {
            $arch = Select-FromList "Select FreeBSD architecture" @("arm64", "armv5", "armv6", "armv7", "i386", "x86_64")
            return "freebsd_$arch"
        }
        "linux" {
            $arch = Select-FromList "Select Linux architecture" @("arm64", "armv5", "armv6", "armv7", "i386", "mips", "mipsle", "mips64", "mips64le", "riscv64", "x86_64")
            if ($arch -like "mips*") {
                $float = Select-FromList "Select MIPS float ABI" @("softfloat", "hardfloat")
                return "linux_$arch`_$float"
            }
            return "linux_$arch"
        }
        "windows" {
            $arch = Select-FromList "Select Windows architecture" @("arm64", "i386", "x86_64")
            return "windows_$arch"
        }
    }
}

function Confirm-OrSelectTarget {
    param(
        [string]$DetectedTarget,
        [string]$DetectedOS,
        [string]$DetectedArch,
        [string]$VersionNoPrefix,
        [string]$EffectiveConfig
    )
    $target = $DetectedTarget
    while ($true) {
        $assetName = Get-AssetName -VersionNoPrefix $VersionNoPrefix -Target $target
        $url = "https://github.com/$Repo/releases/download/v$VersionNoPrefix/$assetName"
        Write-Host ""
        Write-Host "Detected system:"
        Write-Host "  OS:            $DetectedOS"
        Write-Host "  Architecture:  $DetectedArch"
        Write-Host "  Target:        $target"
        Write-Host "  Asset:         $assetName"
        Write-Host "  Download URL:  $url"
        Write-Host "  Install dir:   $InstallDir"
        Write-Host "  Config path:   $EffectiveConfig"
        Write-Host "  Listen:        $(Get-ListenAddress)"
        Write-Host ""
        $answer = Read-Host "Use this detected result and continue? [Y/n/m]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            $answer = "Y"
        }
        switch -Regex ($answer) {
            "^(Y|y|yes|YES)$" { return $target }
            "^(N|n|no|NO)$" {
                Write-Host "Canceled."
                exit 0
            }
            "^(M|m)$" {
                $target = Select-ManualTarget
            }
            default {
                Write-Host "Please answer Y, n, or m."
            }
        }
    }
}

function Show-AssetList {
    param([string]$VersionNoPrefix = "6.17.1")
    Write-Host "Official ddns-go release assets covered by this script:"
    Write-Host "  checksums.txt"
    foreach ($target in $SupportedTargets) {
        Write-Host "  $(Get-AssetName -VersionNoPrefix $VersionNoPrefix -Target $target)"
    }
}

function Invoke-Download {
    param(
        [string]$VersionNoPrefix,
        [string]$AssetName,
        [string]$WorkDir
    )
    $baseUrl = "https://github.com/$Repo/releases/download/v$VersionNoPrefix"
    Invoke-WebRequest -Uri "$baseUrl/$AssetName" -OutFile (Join-Path $WorkDir $AssetName)
    Invoke-WebRequest -Uri "$baseUrl/checksums.txt" -OutFile (Join-Path $WorkDir "checksums.txt")
}

function Test-Checksum {
    param(
        [string]$AssetName,
        [string]$WorkDir
    )
    $checksumFile = Join-Path $WorkDir "checksums.txt"
    $assetPath = Join-Path $WorkDir $AssetName
    $line = Get-Content -LiteralPath $checksumFile | Where-Object { $_ -match [regex]::Escape($AssetName) } | Select-Object -First 1
    if (-not $line) {
        throw "No checksum entry found for $AssetName."
    }
    $expected = ($line -split "\s+")[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "Checksum mismatch for $AssetName. Expected $expected but got $actual."
    }
    Write-Host "Checksum OK: $AssetName"
}

function Expand-Asset {
    param(
        [string]$AssetName,
        [string]$WorkDir
    )
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    $archive = Join-Path $WorkDir $AssetName
    if ($AssetName.EndsWith(".zip")) {
        Expand-Archive -LiteralPath $archive -DestinationPath $InstallDir -Force
        return
    }
    tar -xzf $archive -C $InstallDir
}

function Get-BinaryPath {
    param([string]$Target)
    if ($Target.StartsWith("windows_")) {
        return Join-Path $InstallDir "ddns-go.exe"
    }
    return Join-Path $InstallDir "ddns-go"
}

function Install-ServiceOrPrintHint {
    param(
        [string]$Target,
        [string]$EffectiveConfig
    )
    $binary = Get-BinaryPath -Target $Target
    if ($Target.StartsWith("windows_")) {
        & $binary -s install -l (Get-ListenAddress) -f $Interval -c $EffectiveConfig
        return
    }
    Write-Host "$Target was selected. Service installation is skipped in PowerShell."
    Write-Host "Use install-ddns-go.sh on Unix-like systems, or run manually:"
    Write-Host "$binary -l $(Get-ListenAddress) -f $Interval -c $EffectiveConfig"
}

function Resolve-Command {
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        return $Command
    }
    if ([Console]::IsInputRedirected) {
        return "install"
    }
    return Select-FromList "Select operation mode (Up/Down, Enter)" @("install", "update", "uninstall", "status", "list")
}

function Resolve-ListenSettings {
    if (-not [string]::IsNullOrWhiteSpace($Listen) -or -not [string]::IsNullOrWhiteSpace($Ip)) {
        return
    }
    if ([Console]::IsInputRedirected) {
        return
    }

    $mode = Select-FromList "Select Web listen mode (Up/Down, Enter)" @(
        "Public IPv4 (0.0.0.0:$Port)",
        "Localhost only (127.0.0.1:$Port)",
        "Custom public port",
        "Custom local port",
        "Custom full listen address"
    )
    switch -Wildcard ($mode) {
        "Public IPv4*" { $script:Ip = "0.0.0.0" }
        "Localhost only*" { $script:Ip = "127.0.0.1" }
        "Custom public port" {
            $answer = Read-Host "Input public Web port, for example 9876"
            $portValue = 0
            if (-not [int]::TryParse($answer, [ref]$portValue) -or $portValue -lt 1 -or $portValue -gt 65535) {
                throw "Port must be a number between 1 and 65535."
            }
            $script:Port = $portValue
            $script:Ip = "0.0.0.0"
        }
        "Custom local port" {
            $answer = Read-Host "Input local Web port, for example 9876"
            $portValue = 0
            if (-not [int]::TryParse($answer, [ref]$portValue) -or $portValue -lt 1 -or $portValue -gt 65535) {
                throw "Port must be a number between 1 and 65535."
            }
            $script:Port = $portValue
            $script:Ip = "127.0.0.1"
        }
        "Custom full listen address" {
            $answer = Read-Host "Input listen address, for example 0.0.0.0:9876 or [::]:9876"
            if ([string]::IsNullOrWhiteSpace($answer)) { throw "Listen address cannot be empty." }
            $script:Listen = $answer
        }
    }
}

function Invoke-InstallOrUpdate {
    param([string]$Action)
    if (-not (Test-Administrator)) {
        throw "Please run PowerShell as Administrator."
    }

    $effectiveVersion = Resolve-Version
    Resolve-ListenSettings
    $versionNoPrefix = Get-VersionWithoutPrefix $effectiveVersion
    $effectiveConfig = if ([string]::IsNullOrWhiteSpace($Config)) {
        Join-Path $InstallDir ".ddns_go_config.yaml"
    } else {
        $Config
    }

    if ([string]::IsNullOrWhiteSpace($Asset)) {
        $detected = Get-DetectedTarget
        $target = Confirm-OrSelectTarget -DetectedTarget $detected.Target -DetectedOS $detected.OS -DetectedArch $detected.Architecture -VersionNoPrefix $versionNoPrefix -EffectiveConfig $effectiveConfig
        $assetName = Get-AssetName -VersionNoPrefix $versionNoPrefix -Target $target
    } else {
        $assetName = $Asset
        $target = Get-TargetFromAsset -AssetName $assetName -VersionNoPrefix $versionNoPrefix
        if ($SupportedTargets -notcontains $target) {
            throw "Unsupported asset target: $target"
        }
    }

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ddns-go-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    try {
        if ($Action -eq "update") {
            Stop-Service -Name "ddns-go" -ErrorAction SilentlyContinue
        }
        Invoke-Download -VersionNoPrefix $versionNoPrefix -AssetName $assetName -WorkDir $workDir
        Test-Checksum -AssetName $assetName -WorkDir $workDir
        Expand-Asset -AssetName $assetName -WorkDir $workDir
        Install-ServiceOrPrintHint -Target $target -EffectiveConfig $effectiveConfig
    } finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force
        }
    }

    Write-Host ""
    Write-Host "ddns-go $Action finished."
    Write-AccessUrls
    Write-Host "Config: $effectiveConfig"
}

function Invoke-Uninstall {
    if (-not (Test-Administrator)) {
        throw "Please run PowerShell as Administrator."
    }
    $binary = Join-Path $InstallDir "ddns-go.exe"
    if (Test-Path -LiteralPath $binary) {
        & $binary -s uninstall
    } else {
        Stop-Service -Name "ddns-go" -ErrorAction SilentlyContinue
    }
    $answer = Read-Host "Remove install directory and config at $InstallDir? [y/N]"
    if ($answer -match "^(Y|y|yes|YES)$") {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host "Removed $InstallDir."
    } else {
        Write-Host "Kept $InstallDir."
    }
}

function Show-Status {
    $effectiveConfig = if ([string]::IsNullOrWhiteSpace($Config)) {
        Join-Path $InstallDir ".ddns_go_config.yaml"
    } else {
        $Config
    }
    Write-Host "Install dir: $InstallDir"
    Write-Host "Config path: $effectiveConfig"
    $binary = Join-Path $InstallDir "ddns-go.exe"
    if (Test-Path -LiteralPath $binary) {
        & $binary -v
    }
    Get-Service -Name "ddns-go" -ErrorAction SilentlyContinue | Format-List Name,Status,StartType
    Write-AccessUrls
}

$resolvedCommand = Resolve-Command
switch ($resolvedCommand) {
    "install" { Invoke-InstallOrUpdate -Action "install" }
    "update" { Invoke-InstallOrUpdate -Action "update" }
    "uninstall" { Invoke-Uninstall }
    "status" { Show-Status }
    "list" {
        $versionNoPrefix = if ([string]::IsNullOrWhiteSpace($Version)) { "6.17.1" } else { Get-VersionWithoutPrefix $Version }
        Show-AssetList -VersionNoPrefix $versionNoPrefix
    }
}

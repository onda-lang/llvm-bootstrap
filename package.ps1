param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$Platform,
    [Parameter(Mandatory = $true)]
    [string]$Architecture,
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [ValidateSet("Static", "Shared")]
    [string]$Linkage = "Static",
    [ValidateSet("MD", "MT")]
    [string]$MsvcRuntime = "MT",
    [string]$LlvmRef = ""
)

$ErrorActionPreference = "Stop"

function Get-FirstLine([string]$Path, [string[]]$Arguments) {
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process `
            -FilePath $Path `
            -ArgumentList $Arguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdoutLines = if (Test-Path $stdoutPath) { Get-Content -Path $stdoutPath } else { @() }
        $stderrLines = if (Test-Path $stderrPath) { Get-Content -Path $stderrPath } else { @() }
        $output = @($stdoutLines) + @($stderrLines)

        if ($process.ExitCode -ne 0 -and -not $output) {
            return ""
        }
        return ($output | Select-Object -First 1).ToString().Trim()
    } finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force
            }
        }
    }
}

function Get-ToolVersion([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        return ""
    }
    return $command.Source
}

$linkageToken = $Linkage.ToLowerInvariant()
$runtimeToken = ""
$archiveName = "llvm-$Version-$Platform-$Architecture-$linkageToken$runtimeToken.zip"
$archivePath = Join-Path $OutputDir $archiveName
$manifestDir = Join-Path $InstallDir "share\llvm-bootstrap"
$manifestPath = Join-Path $manifestDir "BUILDINFO.json"
$llvmLicense = Join-Path $InstallDir "share\licenses\llvm\LICENSE.TXT"
$blake3License = Join-Path $InstallDir "share\licenses\llvm\BLAKE3-LICENSE.txt"
$xxhashLicense = Join-Path $InstallDir "share\licenses\llvm\XXHASH-LICENSE.txt"
$md5License = Join-Path $InstallDir "share\licenses\llvm\MD5-LICENSE.txt"
$regexLicense = Join-Path $InstallDir "share\licenses\llvm\REGEX-LICENSE.txt"
$unicodeLicense = Join-Path $InstallDir "share\licenses\llvm\UNICODE-LICENSE.txt"
$msvcSetupApiLicense = Join-Path $InstallDir "share\licenses\llvm\MSVCSETUPAPI-LICENSE.txt"

if (-not (Test-Path $llvmLicense)) {
    throw "Complete LLVM license not found at $llvmLicense"
}

if (-not (Test-Path $blake3License) -or
    -not (Test-Path $xxhashLicense) -or
    -not (Test-Path $md5License) -or
    -not (Test-Path $regexLicense) -or
    -not (Test-Path $unicodeLicense) -or
    -not (Test-Path $msvcSetupApiLicense)) {
    throw "Complete LLVM third-party license material not found under $InstallDir\share\licenses\llvm"
}
$blake3LicenseText = Get-Content $blake3License -Raw
$xxhashLicenseText = Get-Content $xxhashLicense -Raw
$md5LicenseText = Get-Content $md5License -Raw
$regexLicenseText = Get-Content $regexLicense -Raw
$unicodeLicenseText = Get-Content $unicodeLicense -Raw
$msvcSetupApiLicenseText = Get-Content $msvcSetupApiLicense -Raw
if (-not ($blake3LicenseText -match "CC0 1.0 Universal") -or
    -not ($xxhashLicenseText -match "Copyright \(C\) 2012-2023, Yann Collet") -or
    -not ($xxhashLicenseText -match "Redistributions in binary form must reproduce") -or
    -not ($md5LicenseText -match "Alexander Peslyak") -or
    -not ($regexLicenseText -match "Henry Spencer") -or
    -not ($regexLicenseText -match "Todd C. Miller") -or
    -not ($unicodeLicenseText -match "1991-2015 Unicode") -or
    -not ($unicodeLicenseText -match "1991-2022 Unicode") -or
    -not ($msvcSetupApiLicenseText -match "Copyright \(C\) Microsoft Corporation")) {
    throw "Complete LLVM third-party license material not found under $InstallDir\share\licenses\llvm"
}
$llvmLicenseText = Get-Content $llvmLicense -Raw
if (-not ($llvmLicenseText -match "Apache License v2.0 with LLVM Exceptions") -or
    -not ($llvmLicenseText -match "END OF TERMS AND CONDITIONS")) {
    throw "Complete LLVM license not found at $llvmLicense"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null

$cmakeVersion = Get-FirstLine "cmake" @("--version")
$ninjaVersion = Get-FirstLine "ninja" @("--version")
$clVersion = if (Get-Command "cl.exe" -ErrorAction SilentlyContinue) { Get-FirstLine "cmd.exe" @("/d", "/c", "cl.exe /Bv") } else { "" }
$linkVersion = if (Get-Command "link.exe" -ErrorAction SilentlyContinue) { Get-FirstLine "cmd.exe" @("/d", "/c", "link.exe") } else { "" }

$manifest = [ordered]@{
    package_version = 1
    llvm_version = $Version
    llvm_ref = $LlvmRef
    platform = $Platform
    architecture = $Architecture
    linkage = $Linkage
    runtime = if ($Platform -eq "windows") { $MsvcRuntime } else { "" }
    archive_name = $archiveName
    generator = "Ninja"
    cmake_version = $cmakeVersion
    ninja_version = $ninjaVersion
    llvm_config_version = Get-FirstLine (Join-Path $InstallDir "bin\llvm-config.exe") @("--version")
    runner_os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    host_architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    visual_studio_version = $env:VisualStudioVersion
    vc_tools_version = $env:VCToolsVersion
    vc_tools_install_dir = $env:VCToolsInstallDir
    windows_sdk_version = $env:WindowsSDKVersion
    windows_sdk_dir = $env:WindowsSdkDir
    cl_path = Get-ToolVersion "cl.exe"
    cl_version = $clVersion
    link_path = Get-ToolVersion "link.exe"
    link_version = $linkVersion
    cmake_msvc_runtime_library = if ($Platform -eq "windows") {
        if ($MsvcRuntime -eq "MT") { "MultiThreaded" } else { "MultiThreadedDLL" }
    } else {
        ""
    }
}

$manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding utf8

if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

Compress-Archive -Path (Join-Path $InstallDir "*") -DestinationPath $archivePath -CompressionLevel Optimal

if (-not (Test-Path $archivePath)) {
    throw "Failed to produce archive at $archivePath"
}

Write-Host $archivePath

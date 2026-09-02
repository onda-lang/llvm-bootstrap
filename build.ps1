param(
    [Parameter(Mandatory = $true)]
    [string]$LlvmRef,
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$BuildDir,
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,
    [ValidateSet("Static", "Shared")]
    [string]$Linkage = "Static",
    [ValidateSet("MD", "MT")]
    [string]$MsvcRuntime = "MT"
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $true
}

function Get-CommentBlock([string]$Path, [int]$Index) {
    $block = 0
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content $Path -Encoding UTF8) {
        if ($line.StartsWith("/*")) { $block++ }
        if ($block -eq $Index) {
            $lines.Add($line)
            if ($line.Trim() -eq "*/") { return $lines.ToArray() }
        }
    }
    throw "Comment block $Index not found in $Path"
}

function Write-Utf8Lines([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllLines(
        $Path,
        $Lines,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$targets = "X86;AArch64;WebAssembly"
$generator = "Ninja"
$llvmSourceDir = Join-Path $SourceDir "llvm"
$runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows
)

$shared = $Linkage -eq "Shared"
$cmakeRuntime = switch ($MsvcRuntime) {
    "MT" { "MultiThreaded" }
    "MD" { "MultiThreadedDLL" }
    default { throw "Unsupported MSVC runtime mode: $MsvcRuntime" }
}

$configureArgs = @(
    "-Wno-dev",
    "-S", $llvmSourceDir,
    "-B", $BuildDir,
    "-G", $generator,
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_INSTALL_PREFIX=$InstallDir",
    "-DLLVM_ENABLE_ASSERTIONS=OFF",
    "-DLLVM_ABI_BREAKING_CHECKS=FORCE_OFF",
    "-DLLVM_ENABLE_PROJECTS=",
    "-DLLVM_TARGETS_TO_BUILD=$targets",
    "-DLLVM_INCLUDE_TESTS=OFF",
    "-DLLVM_INCLUDE_BENCHMARKS=OFF",
    "-DLLVM_INCLUDE_EXAMPLES=OFF",
    "-DLLVM_INCLUDE_DOCS=OFF",
    "-DLLVM_ENABLE_ZLIB=OFF",
    "-DLLVM_ENABLE_ZSTD=OFF",
    "-DLLVM_ENABLE_LIBXML2=OFF"
)

if ($shared) {
    $configureArgs += @(
        "-DBUILD_SHARED_LIBS=ON",
        "-DLLVM_BUILD_LLVM_DYLIB=ON",
        "-DLLVM_BUILD_LLVM_C_DYLIB=ON",
        "-DLLVM_LINK_LLVM_DYLIB=ON"
    )
} else {
    $configureArgs += @(
        "-DBUILD_SHARED_LIBS=OFF",
        "-DLLVM_BUILD_LLVM_DYLIB=OFF",
        "-DLLVM_BUILD_LLVM_C_DYLIB=OFF",
        "-DLLVM_LINK_LLVM_DYLIB=OFF"
    )
}

if ($runningOnWindows) {
    $configureArgs += "-DCMAKE_MSVC_RUNTIME_LIBRARY=$cmakeRuntime"
} else {
    $configureArgs += "-DLLVM_ENABLE_TERMINFO=OFF"
}

cmake @configureArgs
if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed with exit code $LASTEXITCODE"
}

cmake --build $BuildDir --config Release --target install
if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed with exit code $LASTEXITCODE"
}

$llvmLicenseSource = Join-Path $llvmSourceDir "LICENSE.TXT"
$blake3LicenseSource = Join-Path $llvmSourceDir "lib/Support/BLAKE3/LICENSE"
$xxhashSource = Join-Path $llvmSourceDir "lib/Support/xxhash.cpp"
$md5Source = Join-Path $llvmSourceDir "lib/Support/MD5.cpp"
$regexLicenseSource = Join-Path $llvmSourceDir "lib/Support/COPYRIGHT.regex"
$strlcpySource = Join-Path $llvmSourceDir "lib/Support/regstrlcpy.c"
$convertUtfSource = Join-Path $llvmSourceDir "lib/Support/ConvertUTF.cpp"
$unicodeDataSource = Join-Path $llvmSourceDir "lib/Support/UnicodeNameToCodepointGenerated.cpp"
$msvcSetupApiSource = Join-Path $llvmSourceDir "include/llvm/WindowsDriver/MSVCSetupApi.h"
$llvmLicenseDir = Join-Path $InstallDir "share/licenses/llvm"
$llvmLicense = Join-Path $llvmLicenseDir "LICENSE.TXT"
$blake3License = Join-Path $llvmLicenseDir "BLAKE3-LICENSE.txt"
$xxhashLicense = Join-Path $llvmLicenseDir "XXHASH-LICENSE.txt"
$md5License = Join-Path $llvmLicenseDir "MD5-LICENSE.txt"
$regexLicense = Join-Path $llvmLicenseDir "REGEX-LICENSE.txt"
$unicodeLicense = Join-Path $llvmLicenseDir "UNICODE-LICENSE.txt"
$msvcSetupApiLicense = Join-Path $llvmLicenseDir "MSVCSETUPAPI-LICENSE.txt"
if (-not (Test-Path $llvmLicenseSource) -or
    -not (Test-Path $blake3LicenseSource) -or
    -not (Test-Path $xxhashSource) -or
    -not (Test-Path $md5Source) -or
    -not (Test-Path $regexLicenseSource) -or
    -not (Test-Path $strlcpySource) -or
    -not (Test-Path $convertUtfSource) -or
    -not (Test-Path $unicodeDataSource) -or
    -not (Test-Path $msvcSetupApiSource)) {
    throw "LLVM license material is missing from $llvmSourceDir"
}
New-Item -ItemType Directory -Force -Path $llvmLicenseDir | Out-Null
Copy-Item $llvmLicenseSource $llvmLicense -Force
Copy-Item $blake3LicenseSource $blake3License -Force
Write-Utf8Lines $xxhashLicense (Get-CommentBlock $xxhashSource 1)
Write-Utf8Lines $md5License (Get-CommentBlock $md5Source 1)
[string[]]$regexLicenseLines = @(
    Get-Content $regexLicenseSource -Encoding UTF8
    ""
    "Additional llvm_strlcpy notice"
    "================================"
    ""
    Get-CommentBlock $strlcpySource 1
)
Write-Utf8Lines $regexLicense $regexLicenseLines
[string[]]$unicodeLicenseLines = @(
    "ConvertUTF notice"
    "================="
    ""
    Get-CommentBlock $convertUtfSource 2
    ""
    "Unicode data notice"
    "==================="
    ""
    Get-CommentBlock $unicodeDataSource 1
)
Write-Utf8Lines $unicodeLicense $unicodeLicenseLines
$msvcSetupApiLicenseLines = foreach ($line in Get-Content $msvcSetupApiSource -Encoding UTF8) {
    $line
    if ($line -eq "// </license>") { break }
}
Write-Utf8Lines $msvcSetupApiLicense $msvcSetupApiLicenseLines
$llvmLicenseText = Get-Content $llvmLicense -Raw
if (-not ($llvmLicenseText -match "Apache License v2.0 with LLVM Exceptions") -or
    -not ($llvmLicenseText -match "END OF TERMS AND CONDITIONS")) {
    throw "Installed LLVM license is incomplete"
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
    throw "Installed LLVM third-party license material is incomplete"
}

$llvmConfig = Join-Path $InstallDir "bin/llvm-config.exe"
if (-not (Test-Path $llvmConfig)) {
    throw "llvm-config.exe not found at $llvmConfig after build"
}

$coreLib = if ($shared) {
    Join-Path $InstallDir "lib/LLVM.lib"
} else {
    Join-Path $InstallDir "lib/LLVMCore.lib"
}

if (-not (Test-Path $coreLib)) {
    throw "Expected LLVM library not found at $coreLib after build"
}

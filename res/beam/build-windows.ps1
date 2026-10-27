# Builds the Beam portable exe on a Windows 10/11 x64 PC.
# Mirrors .github/workflows/beam-windows.yml, which cannot run while GitHub
# Actions is disabled on the fork. Safe to re-run: finished steps are skipped.
#
#   powershell -ExecutionPolicy Bypass -File res\beam\build-windows.ps1

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Invoke-WebRequest is very slow with the progress bar

$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$Tools = "C:\beam-tools"
$FlutterVersion = "3.24.5"
$LlvmVersion = "15.0.6"
$RustVersion = "1.75"
$VcpkgCommit = "9e593bb18ea69cc5095e012465dcd675a822ed0d"
$Version = "1.5.1"
$LlvmBin = "C:\Program Files\LLVM\bin"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }

function Run($exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $exe $($arguments -join ' ')" }
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
                "$env:USERPROFILE\.cargo\bin;$LlvmBin;$Tools\flutter\bin"
}

function Works($exe, [string[]]$arguments) {
    try { & $exe @arguments *> $null; return $LASTEXITCODE -eq 0 } catch { return $false }
}

# Windows ships a 'python' stub that only opens the Store, and a fresh install
# is often not on PATH yet, so ask a real interpreter for its own path.
function Find-Python {
    $probe = "import sys; print(sys.executable)"
    foreach ($try in @({ py -3 -c $probe }, { python -c $probe })) {
        try {
            $path = & $try 2>$null
            if ($LASTEXITCODE -eq 0 -and $path) { return "$path".Trim() }
        } catch {}
    }
    return $null
}

function Winget-Install($id, [string[]]$extra = @()) {
    Run winget (@("install", "-e", "--id", $id, "--accept-package-agreements", "--accept-source-agreements") + $extra)
    Refresh-Path
}

New-Item -ItemType Directory -Force -Path $Tools | Out-Null
Refresh-Path

Step "Checking free disk space"
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB)
Write-Host "Free on C: $freeGb GB"
if ($freeGb -lt 30) { throw "At least 30 GB free on C: are needed, found $freeGb GB." }

Step "Python"
$Python = Find-Python
if (-not $Python) { Winget-Install "Python.Python.3.11"; $Python = Find-Python }
if (-not $Python) { throw "Python was installed but is not found yet. Open a new PowerShell window and run the script again." }
Write-Host "Using $Python"

Step "Visual Studio 2022 Build Tools (C++)"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = if (Test-Path $vswhere) {
    & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (-not $vs) {
    Write-Host "Installing (takes 10-20 min, Windows will ask for admin rights)..."
    Winget-Install "Microsoft.VisualStudio.2022.BuildTools" @("--override",
        "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended")
}

Step "LLVM $LlvmVersion"
if (-not (Test-Path "$LlvmBin\libclang.dll")) {
    $installer = "$Tools\LLVM-$LlvmVersion-win64.exe"
    Invoke-WebRequest "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LlvmVersion/LLVM-$LlvmVersion-win64.exe" -OutFile $installer
    Start-Process $installer -ArgumentList "/S" -Verb RunAs -Wait
}
$env:LIBCLANG_PATH = $LlvmBin

Step "Rust $RustVersion"
if (-not (Works rustup @("--version"))) { Winget-Install "Rustlang.Rustup" }
Run rustup @("toolchain", "install", $RustVersion, "--profile", "minimal", "--component", "rustfmt")
$env:RUSTUP_TOOLCHAIN = $RustVersion

Step "Flutter $FlutterVersion with the RustDesk engine"
$Flutter = "$Tools\flutter"
if (-not (Test-Path "$Flutter\bin\flutter.bat")) {
    $zip = "$Tools\flutter.zip"
    Write-Host "Downloading Flutter (~1 GB)..."
    Invoke-WebRequest "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip" -OutFile $zip
    Run tar @("-xf", $zip, "-C", $Tools)
    Remove-Item $zip
}
Run flutter @("config", "--no-analytics")
if (-not (Test-Path "$Flutter\.beam-ready")) {
    Run flutter @("precache", "--windows")
    # https://github.com/flutter/flutter/issues/155685
    $engineZip = "$Tools\windows-x64-release.zip"
    Invoke-WebRequest "https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip" -OutFile $engineZip
    Remove-Item -Recurse -Force "$Tools\engine" -ErrorAction SilentlyContinue
    Run tar @("-xf", $engineZip, "-C", (New-Item -ItemType Directory -Force "$Tools\engine").FullName)
    Copy-Item -Recurse -Force "$Tools\engine\*" "$Flutter\bin\cache\artifacts\engine\windows-x64-release\"
    Run git @("-C", $Flutter, "apply", "$Repo\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff")
    New-Item -ItemType File "$Flutter\.beam-ready" | Out-Null
}

Step "vcpkg libraries (first run: 30-60 min)"
$Vcpkg = "$Tools\vcpkg"
if (-not (Test-Path "$Vcpkg\vcpkg.exe")) {
    if (-not (Test-Path $Vcpkg)) { Run git @("clone", "https://github.com/microsoft/vcpkg", $Vcpkg) }
    Run git @("-C", $Vcpkg, "checkout", $VcpkgCommit)
    Run "$Vcpkg\bootstrap-vcpkg.bat" @("-disableMetrics")
}
$env:VCPKG_ROOT = $Vcpkg
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"
Push-Location $Repo
try {
    Run "$Vcpkg\vcpkg.exe" @("install", "--triplet", "x64-windows-static", "--x-install-root=$Vcpkg\installed")

    Step "Flutter-Rust bridge (pre-generated by the last GitHub build)"
    Copy-Item -Recurse -Force "$Repo\res\beam\bridge\*" $Repo

    Step "Building Beam (first run: 20-40 min)"
    Run $Python @(".\build.py", "--portable", "--flutter", "--skip-portable-pack", "--hwcodec", "--vram")
    Remove-Item -Recurse -Force .\rustdesk -ErrorAction SilentlyContinue
    Move-Item .\flutter\build\windows\x64\runner\Release .\rustdesk

    $usb = "$Tools\usbmmidd_v2.zip"
    Invoke-WebRequest "https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip" -OutFile $usb
    Remove-Item -Recurse -Force .\usbmmidd_v2 -ErrorAction SilentlyContinue
    Expand-Archive $usb -DestinationPath .
    Remove-Item -Recurse .\usbmmidd_v2\Win32
    Remove-Item .\usbmmidd_v2\deviceinstaller64.exe, .\usbmmidd_v2\deviceinstaller.exe, .\usbmmidd_v2\usbmmidd.bat
    Move-Item .\usbmmidd_v2 .\rustdesk

    $runnerRes = Get-ChildItem -Recurse -Filter Runner.res -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($runnerRes) { Copy-Item $runnerRes.FullName .\libs\portable\Runner.res -Force }

    Step "Packing the portable exe"
    # Same manifest tweak as CI; restored afterwards so the checkout stays clean.
    (Get-Content res\manifest.xml) | Where-Object { $_ -notmatch "dpiAware" } | Set-Content res\manifest.xml
    try {
        Run $Python @("-m", "pip", "install", "-r", "libs\portable\requirements.txt")
        Push-Location libs\portable
        try { Run $Python @(".\generate.py", "-f", "..\..\rustdesk\", "-o", ".", "-e", "..\..\rustdesk\rustdesk.exe") }
        finally { Pop-Location }
    }
    finally { Run git @("checkout", "--", "res\manifest.xml") }

    New-Item -ItemType Directory -Force .\Output | Out-Null
    $out = ".\Output\beam-$Version-x64-portable.exe"
    Move-Item -Force .\target\release\rustdesk-portable-packer.exe $out
    $size = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "`nDone: $((Resolve-Path $out).Path) ($size MB)" -ForegroundColor Green
}
finally { Pop-Location }

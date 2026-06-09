# Roblox.ps1 - one-click Roblox bypass (zapret-roblox engine)
param(
    [ValidateSet("go", "stop", "fix", "menu", "diag")]
    [string]$Action = "go"
)

$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot
$InstallDir = Join-Path $Root "installed"
$ZapretDir = Join-Path $InstallDir "zapret2.0"
$BinDir = Join-Path $ZapretDir "bin"
$ListsDir = Join-Path $Root "lists"
$PidFile = Join-Path $Root ".roblox.pid"
$ZipUrl = "https://github.com/vwercay/zapret-roblox/archive/refs/heads/main.zip"

function Write-Msg([string]$Text, [string]$Color = "White") {
    Write-Host $Text -ForegroundColor $Color
}

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Installed {
    return Test-Path (Join-Path $BinDir "winws.exe")
}

function Install-Engine {
    if (Test-Installed) {
        Write-Msg "[OK] Already installed." "Green"
        return $true
    }

    Write-Msg "Downloading zapret-roblox..." "Cyan"
    $zip = Join-Path $env:TEMP "zapret-roblox.zip"
    $extract = Join-Path $env:TEMP "zapret-roblox-unpack"

    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force

        $source = Join-Path $extract "zapret-roblox-main\zapret2.0"
        if (-not (Test-Path (Join-Path $source "bin\winws.exe"))) {
            Write-Msg "[FAIL] winws.exe missing in download." "Red"
            return $false
        }

        if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
        Copy-Item $source $ZapretDir -Recurse -Force

        $zLists = Join-Path $ZapretDir "lists"
        Copy-Item (Join-Path $ListsDir "list-roblox.txt") (Join-Path $zLists "list-general.txt") -Force
        Copy-Item (Join-Path $ListsDir "ipset-roblox.txt") (Join-Path $zLists "ipset-all.txt.backup") -Force
        Set-Content (Join-Path $zLists "ipset-all.txt") "" -Encoding ASCII

        $utils = Join-Path $ZapretDir "utils"
        New-Item -ItemType Directory -Path $utils -Force | Out-Null
        Set-Content (Join-Path $utils "game_filter.enabled") "all" -Encoding ASCII

        Write-Msg "[OK] Installed in ~10 sec. Ready." "Green"
        return $true
    } catch {
        Write-Msg "[FAIL] $($_.Exception.Message)" "Red"
        return $false
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Stop-RobloxOnly {
    if (Test-Path $PidFile) {
        $pid = [int](Get-Content $PidFile -Raw).Trim()
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        Write-Msg "[OK] Roblox bypass stopped (PID $pid). Your zapret NOT touched." "Green"
        return
    }
    Write-Msg "[OK] Roblox bypass not running." "Yellow"
}

function Start-RobloxBypass {
    $existing = Get-Process -Name "winws" -ErrorAction SilentlyContinue
    if ($existing -and -not (Test-Path $PidFile)) {
        Write-Msg "[INFO] winws already running (your zapret). Using it for Roblox." "Yellow"
        Write-Msg "Make sure zapret has: Game Filter ON + ipset any + Roblox lists." "Yellow"
        return $true
    }

    Stop-RobloxOnly

    $bin = Join-Path $BinDir "winws.exe"
    $list = Join-Path $ListsDir "list-roblox.txt"
    $ipset = Join-Path $ListsDir "ipset-roblox.txt"
    $tls = Join-Path $BinDir "tls_clienthello_www_google_com.bin"
    $quic = Join-Path $BinDir "quic_initial_www_google_com.bin"

    $args = @(
        "--wf-tcp=80,443,1024-65535",
        "--wf-udp=443,49152-65535,1024-65535",
        "--filter-tcp=80,443", "--hostlist=$list",
        "--dpi-desync=multisplit", "--dpi-desync-split-pos=2,sniext+1",
        "--dpi-desync-split-seqovl=679", "--dpi-desync-split-seqovl-pattern=$tls", "--new",
        "--filter-udp=443", "--hostlist=$list",
        "--dpi-desync=fake", "--dpi-desync-repeats=6", "--dpi-desync-fake-quic=$quic", "--new",
        "--filter-tcp=1024-65535", "--ipset=$ipset",
        "--dpi-desync=syndata", "--dpi-desync-any-protocol=1", "--dpi-desync-cutoff=n4", "--new",
        "--filter-udp=49152-65535", "--ipset=$ipset",
        "--dpi-desync=fake", "--dpi-desync-repeats=12", "--dpi-desync-any-protocol=1",
        "--dpi-desync-fake-unknown-udp=$quic", "--dpi-desync-cutoff=n2"
    )

    $proc = Start-Process -FilePath $bin -ArgumentList $args -PassThru -WindowStyle Hidden
    Set-Content -Path $PidFile -Value $proc.Id -Encoding ASCII
    Start-Sleep -Seconds 1
    Write-Msg "[OK] Bypass started (PID $($proc.Id)). Open Roblox." "Green"
    return $true
}

function Repair-Network {
    Write-Msg "Fixing network / black screen..." "Cyan"

    Stop-RobloxOnly

    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
    }
    Clear-DnsClientCache
    ipconfig /flushdns | Out-Null

    $warp = Get-Service -Name "CloudflareWARP" -ErrorAction SilentlyContinue
    if ($warp -and $warp.Status -eq "Running") {
        Stop-Service -Name "CloudflareWARP" -Force -ErrorAction SilentlyContinue
        Write-Msg "[OK] WARP stopped (was breaking DNS/display)." "Green"
    }

    Write-Msg "[OK] DNS restored. Black screen should be gone." "Green"
    Write-Msg "If still black on Alt+Tab: Roblox Settings -> Graphics -> fullscreen OFF." "Yellow"
}

function Test-RobloxNet {
    Write-Msg "`n=== Diagnostics ===" "Cyan"
    $urls = @(
        "https://www.roblox.com",
        "https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer"
    )
    foreach ($u in $urls) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 10
            Write-Msg "  [OK] $u" "Green"
        } catch {
            Write-Msg "  [FAIL] $u" "Red"
        }
    }
    $w = Get-Process winws -ErrorAction SilentlyContinue
    if ($w) { Write-Msg "  [OK] bypass running" "Green" }
    else { Write-Msg "  [FAIL] bypass off" "Red" }
}

function Show-Menu {
    Clear-Host
    Write-Msg "========== ROBLOX ==========" "Cyan"
    Write-Msg "1. GO (install + start)" "White"
    Write-Msg "2. Stop Roblox bypass only" "White"
    Write-Msg "3. Fix black screen / network" "White"
    Write-Msg "4. Diagnostics" "White"
    Write-Msg "0. Exit" "White"
    switch (Read-Host "`nChoice") {
        "1" { if (Install-Engine) { Start-RobloxBypass } }
        "2" { Stop-RobloxOnly }
        "3" { Repair-Network }
        "4" { Test-RobloxNet }
        "0" { return }
        default { Write-Msg "Invalid." "Yellow" }
    }
    Read-Host "`nPress Enter"
    Show-Menu
}

if (-not (Test-Admin)) {
    Write-Msg "Need Administrator. Right-click Roblox.bat -> Run as admin." "Red"
    exit 1
}

switch ($Action) {
    "go" {
        Write-Msg "=== ROBLOX GO ===" "Cyan"
        if (Install-Engine) { Start-RobloxBypass }
        Test-RobloxNet
    }
    "stop" { Stop-RobloxOnly }
    "fix" { Repair-Network }
    "diag" { Test-RobloxNet }
    "menu" { Show-Menu }
}

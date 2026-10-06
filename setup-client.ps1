# Adds SSH shortcuts that reach the server through the HTTPS tunnel. Safe to run again.
#   setup-client.ps1 -Server fmd.example.com -User Admin -Name myserver -Fp $fp -Pw $pw
# Creates two shortcuts: "ssh <Name>" (port 22) and "ssh <Name>-8989" (port 8989).
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Fp,
    [Parameter(Mandatory = $true)][string]$Pw,
    [string]$User = $env:USERNAME,
    [string]$Name = "tunnel",
    [string]$Url = ""
)

$ErrorActionPreference = "Stop"
function Ok($m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }

if (-not $Url) { $Url = "https://$Server/sshws/" }
$exe = Join-Path $PSScriptRoot "chisel.exe"
if (-not (Test-Path $exe)) { Fail "chisel.exe is missing from $PSScriptRoot. Download the kit again." }
Unblock-File $exe

# --- 1. Tunnel reachable ----------------------------------------------------

$health = ""
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    $health = ((& curl.exe -s -m 10 "$($Url)health") | Out-String).Trim()
} else {
    try {
        [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
        $health = (Invoke-WebRequest "$($Url)health" -UseBasicParsing -TimeoutSec 10).Content.Trim()
    } catch { }
}
if ($health -ne "OK") {
    Fail "$($Url)health does not answer OK. Check the server setup and any firewall in front of the server."
}
Ok "Tunnel answers at $Url"

# --- 2. Password, fingerprint and both SSH ports ----------------------------

function Get-SshBanner([int]$port) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "client --max-retry-count 0 --fingerprint $Fp --auth tunnel:$Pw $Url stdio:127.0.0.1:$port"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $line = $p.StandardOutput.ReadLineAsync()
    $done = $line.Wait(15000)
    try { $p.Kill() } catch { }
    if ($done -and $line.Result -like "SSH-*") { return $line.Result }
    $err = ($p.StandardError.ReadToEnd() -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    return "ERROR $err"
}

$b22 = Get-SshBanner 22
if ($b22 -notlike "SSH-*") { Fail "Port 22 through the tunnel failed. Check the two lines from the server. chisel said: $b22" }
Ok "Port 22 answers: $b22"
$b8989 = Get-SshBanner 8989
if ($b8989 -like "SSH-*") { Ok "Port 8989 answers: $b8989" }
else { Warn "Port 8989 does not answer through the tunnel. Only 'ssh $Name' will work. chisel said: $b8989" }

# --- 3. SSH config ----------------------------------------------------------

$dir = Join-Path $HOME ".ssh"
New-Item -ItemType Directory -Force $dir | Out-Null
$cfg = Join-Path $dir "config"
$old = @()
if (Test-Path $cfg) {
    $old = @(Get-Content $cfg)
    Copy-Item $cfg "$cfg.bak-sshtunnel" -Force
}

# Drop earlier blocks with the same names, keep everything else.
$keep = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($l in $old) {
    if ($l -match '^\s*(Host|Match)\s+(.+?)\s*$') {
        $skip = ($Matches[1] -eq "Host") -and ($Matches[2] -eq $Name -or $Matches[2] -eq "$Name-8989")
    }
    if (-not $skip) { $keep.Add($l) }
}
while ($keep.Count -gt 0 -and -not $keep[$keep.Count - 1].Trim()) { $keep.RemoveAt($keep.Count - 1) }

$exeCfg = $exe -replace '\\', '/'
if ($exeCfg -match ' ') { $exeCfg = "`"$exeCfg`"" }
$pc = "$exeCfg client --max-retry-count 0 --fingerprint $Fp --auth tunnel:$Pw $Url"
foreach ($entry in @(@($Name, 22), @("$Name-8989", 8989))) {
    $keep.Add("")
    $keep.Add("Host $($entry[0])")
    $keep.Add("  HostName 127.0.0.1")
    $keep.Add("  User $User")
    $keep.Add("  HostKeyAlias $Server")
    $keep.Add("  ProxyCommand $pc stdio:127.0.0.1:$($entry[1])")
}
[IO.File]::WriteAllLines($cfg, $keep)
Ok "Shortcuts written to $cfg"

Write-Host ""
Write-Host "Setup complete. Connect with:" -ForegroundColor Green
Write-Host "ssh $Name" -ForegroundColor Yellow
if ($b8989 -like "SSH-*") { Write-Host "ssh $Name-8989" -ForegroundColor Yellow }
Write-Host ""

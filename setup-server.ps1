# Sets up the SSH-over-HTTPS tunnel on this server. Safe to run again.
#   setup-server.ps1           install, or repair an earlier install
#   setup-server.ps1 -Remove   undo every change except this folder
param(
    [switch]$Remove,
    [string]$CheckUrl = "https://localhost/sshws/health"
)

$ErrorActionPreference = "Stop"
$d      = $PSScriptRoot
$task   = "SshTunnel"
$port   = 47900
$inc    = "Include conf/extra/apache-sshtunnel.conf"
$marker = "# sshtunnel"
$proxy  = "ProxyPass `"/sshws/`" `"ws://127.0.0.1:$port/`""

function Ok($m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Step($m) { Write-Host "[..]   $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }

function Get-Health($url) {
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        return ((& curl.exe -sk -m 5 $url) | Out-String).Trim()
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = 'Tls12, Tls11, Tls'
        [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0
        $c = $r.Content
        if ($c -is [byte[]]) { $c = [Text.Encoding]::ASCII.GetString($c) }
        return $c.Trim()
    } catch { return "" }
}

function Test-Apache {
    $out = cmd /c "`"$httpd`" -t -d `"$ap`" -f `"$conf`" 2>&1"
    return ($out | Out-String).Trim()
}

function Restart-Apache {
    $svc = Get-CimInstance Win32_Service |
        Where-Object { $_.PathName -match 'httpd\.exe' -and $_.State -eq 'Running' } |
        Select-Object -First 1
    if ($svc) {
        Restart-Service $svc.Name -Force
        Ok "Apache service '$($svc.Name)' restarted"
    } else {
        Get-Process httpd -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep 2
        Start-Process $httpd -WorkingDirectory $ap -WindowStyle Hidden
        Ok "Apache restarted. The XAMPP Control Panel may show Apache as stopped."
    }
    Start-Sleep 3
    if (-not (Get-Process httpd -ErrorAction SilentlyContinue)) {
        Fail "Apache did not start. Read the last lines of $ap\logs\error.log"
    }
}

# Exact text added to config files. Removal deletes this same text, so files return byte for byte.
$incText   = "$inc`r`n"
$vhostText = "`r`n    $marker`r`n    $proxy"

function Stop-Tunnel {
    # run.cmd restarts chisel in a loop, so stop the loop before chisel.
    Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq 'cmd.exe' -and $_.CommandLine -like "*$d\run.cmd*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process chisel -ErrorAction SilentlyContinue | Stop-Process -Force
}

function Get-SslVhostFiles {
    Get-ChildItem "$ap\conf" -Recurse -Filter *.conf |
        Where-Object { $_.FullName -notmatch '\\original\\' } |
        Where-Object { Select-String -Path $_.FullName -Pattern '^\s*<VirtualHost[^>]*:443' -Quiet }
}

function Add-ProxyToSslVhosts {
    foreach ($f in Get-SslVhostFiles) {
        $raw = [IO.File]::ReadAllText($f.FullName)
        if ($raw.Contains('"/sshws/"')) { continue }
        if (-not (Test-Path "$($f.FullName).bak-sshtunnel")) {
            Copy-Item $f.FullName "$($f.FullName).bak-sshtunnel"
        }
        $pat = '(?s)(<VirtualHost[^>]*:443[^>]*>.*?)(\r?\n[ \t]*</VirtualHost>)'
        $new = [regex]::Replace($raw, $pat, { param($m) $m.Groups[1].Value + $vhostText + $m.Groups[2].Value })
        [IO.File]::WriteAllText($f.FullName, $new)
        Ok "Forward added to the 443 site in $($f.FullName)"
    }
}

# --- Checks -----------------------------------------------------------------

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail "Run PowerShell as Administrator, then run this script again." }

foreach ($f in "chisel.exe", "run.cmd", "apache-sshtunnel.conf") {
    if (-not (Test-Path "$d\$f")) { Fail "$f is missing from $d. Download the kit again." }
}
Get-ChildItem $d -File | Unblock-File

$httpd = (Get-Process httpd -ErrorAction SilentlyContinue | Select-Object -First 1).Path
if (-not $httpd) {
    $svc = Get-CimInstance Win32_Service | Where-Object { $_.PathName -match 'httpd\.exe' } | Select-Object -First 1
    if ($svc -and $svc.PathName -match '^"?([^"]*httpd\.exe)') { $httpd = $Matches[1] }
}
if (-not $httpd) { Fail "Apache is not running. Start Apache, then run this script again." }
$ap   = Split-Path (Split-Path $httpd)
$conf = "$ap\conf\httpd.conf"
if (-not (Test-Path $conf)) { Fail "Apache config not found at $conf" }
Ok "Apache found at $ap"

# --- Remove -----------------------------------------------------------------

if ($Remove) {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
    }
    Stop-Tunnel
    Ok "Tunnel server stopped and removed from startup"

    $raw = [IO.File]::ReadAllText($conf)
    if ($raw.Contains($incText)) { [IO.File]::WriteAllText($conf, $raw.Replace($incText, "")) }
    Remove-Item "$ap\conf\extra\apache-sshtunnel.conf" -ErrorAction SilentlyContinue
    foreach ($f in Get-SslVhostFiles) {
        $raw = [IO.File]::ReadAllText($f.FullName)
        if ($raw.Contains($vhostText)) { [IO.File]::WriteAllText($f.FullName, $raw.Replace($vhostText, "")) }
    }
    $t = Test-Apache
    if ($t -notmatch 'Syntax OK') { Fail "Apache config test failed after removal:`n$t" }
    Ok "Apache forward removed"
    Restart-Apache
    Write-Host ""
    Write-Host "Removal complete. Delete the kit folder with:"
    Write-Host "Remove-Item $d -Recurse -Force" -ForegroundColor Yellow
    exit 0
}

# --- 1. Folder permissions --------------------------------------------------

# SIDs: S-1-5-18 = SYSTEM, S-1-5-32-544 = Administrators (language-independent)
icacls $d /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Could not restrict $d to administrators." }
Ok "Folder restricted to SYSTEM and Administrators"

# --- 2. Password and server key ---------------------------------------------

if (-not (Test-Path "$d\users.json")) {
    $b = New-Object byte[] 18
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $newPw = [Convert]::ToBase64String($b) -replace '[+/=]', 'x'
    $j = '{"tunnel:' + $newPw + '": ["^127.0.0.1:(22|8989)$"]}'
    [IO.File]::WriteAllText("$d\users.json", $j)
    Ok "Tunnel password created"
} else { Ok "Tunnel password kept from the earlier install" }

if (-not (Test-Path "$d\key.pem")) {
    cmd /c "`"$d\chisel.exe`" server --keygen `"$d\key.pem`" 2>&1" | Out-Null
    if (-not (Test-Path "$d\key.pem")) { Fail "chisel could not create key.pem" }
    Ok "Server key created"
} else { Ok "Server key kept from the earlier install" }

# --- 3. Tunnel server at startup --------------------------------------------

if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $task
    Unregister-ScheduledTask -TaskName $task -Confirm:$false
}
Stop-Tunnel

$act = New-ScheduledTaskAction -Execute "$d\run.cmd" -WorkingDirectory $d
$trg = New-ScheduledTaskTrigger -AtStartup
$usr = New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $act -Trigger $trg -Principal $usr -Settings $set | Out-Null
Start-ScheduledTask -TaskName $task

Step "Waiting for the tunnel server"
$h = ""
for ($i = 0; $i -lt 15 -and $h -ne "OK"; $i++) { Start-Sleep 1; $h = Get-Health "http://127.0.0.1:$port/health" }
if ($h -ne "OK") { Fail "The tunnel server did not start. Read $d\chisel.log" }
Ok "Tunnel server running on 127.0.0.1:$port, starts at every boot"

# --- 4. Apache forward ------------------------------------------------------

Copy-Item "$d\apache-sshtunnel.conf" "$ap\conf\extra\" -Force
$raw = [IO.File]::ReadAllText($conf)
if (-not $raw.Contains($inc)) {
    if (-not (Test-Path "$conf.bak-sshtunnel")) { Copy-Item $conf "$conf.bak-sshtunnel" }
    if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { $raw += "`r`n" }
    [IO.File]::WriteAllText($conf, $raw + $incText)
}
$t = Test-Apache
if ($t -notmatch 'Syntax OK') {
    Copy-Item "$conf.bak-sshtunnel" $conf -Force
    Fail "Apache rejected the change, so httpd.conf was restored. Apache said:`n$t"
}
Ok "Apache config accepted"
Restart-Apache

Step "Checking $CheckUrl"
$h = Get-Health $CheckUrl
if ($h -ne "OK") {
    Step "The 443 site ignores the global forward. Adding it inside the 443 site."
    Add-ProxyToSslVhosts
    $t = Test-Apache
    if ($t -notmatch 'Syntax OK') { Fail "Apache rejected the 443 change. Restore the .bak-sshtunnel copy. Apache said:`n$t" }
    Restart-Apache
    $h = Get-Health $CheckUrl
}
if ($h -ne "OK") { Fail "$CheckUrl does not answer OK. Read $ap\logs\error.log" }
Ok "Apache forwards /sshws/ to the tunnel server"

# --- 5. Values for the PC ---------------------------------------------------

$fp = ([regex]'Fingerprint (\S+)').Matches((Get-Content "$d\chisel.log" -Raw)) |
    Select-Object -Last 1 | ForEach-Object { $_.Groups[1].Value }
$pw = ([regex]'tunnel:([^"]+)').Match((Get-Content "$d\users.json" -Raw)).Groups[1].Value

Write-Host ""
Write-Host "Server setup complete. Copy these two lines for your PC:" -ForegroundColor Green
Write-Host ""
Write-Host "`$fp = '$fp'" -ForegroundColor Yellow
Write-Host "`$pw = '$pw'" -ForegroundColor Yellow
Write-Host ""

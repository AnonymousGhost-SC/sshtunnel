# SSH over HTTPS (chisel tunnel)

This kit carries SSH over a WebSocket on port 443. Use it when a firewall in front of the server forwards web traffic (443) and blocks every SSH port.

```
your PC: ssh scra-ws
  └ chisel client ──HTTPS 443──► Apache /sshws/ ──► chisel server 127.0.0.1:47900 ──► sshd 127.0.0.1:22
```

- **chisel** (MIT licence, `LICENSE-chisel.txt`) is a single `.exe` with no dependencies. Version 1.12.0, SHA-256 of the release zip `600a8ad6f03bc7f6d285fd01ab6a3f8a657204adaafa5666ade9451d18df1ebc`.
- The chisel server listens on `127.0.0.1` only. Apache forwards the path `/sshws/` to it.
- Two locks protect the tunnel. The chisel password and the pinned server fingerprint control who can open it. The tunnel user can only reach `127.0.0.1:22` and `127.0.0.1:8989`. Normal SSH login then runs inside the tunnel.

| File | Purpose |
|---|---|
| `chisel.exe` | Tunnel client and server (Windows, 64-bit) |
| `run.cmd` | Starts the chisel server and restarts it 5 seconds after any exit |
| `apache-sshtunnel.conf` | Apache snippet: loads the proxy modules and forwards `/sshws/` |
| `users.json`, `key.pem`, `chisel.log` | Created on the server in Part A. Never committed. |

---

## Rules for pasting

1. Open **PowerShell as Administrator** (Start menu → type `PowerShell` → right-click → **Run as administrator**).
2. Paste **one line at a time** and press Enter after each line.
3. Each step lists the expected output. Stop at any step where the output differs, and fix that step before continuing.
4. A closed PowerShell window loses the variables. Run step A1 again in every new window.

---

## Part A: Server

### A1. Set the variables

```powershell
$d = "C:\sshtunnel"
```
```powershell
$repo = "https://github.com/AnonymousGhost-SC/sshtunnel.git"
```
```powershell
$h = (Get-Process httpd | Select-Object -First 1).Path
```
```powershell
$ap = Split-Path (Split-Path $h)
```
```powershell
$h; $ap
```

**Expected:** two paths, for example `C:\xampp\apache\bin\httpd.exe` and `C:\xampp\apache`.
**No output, or an error:** Apache is not running. Start it from the XAMPP Control Panel, then run A1 again.

### A2. Download the kit

Skip this step if `C:\sshtunnel` already exists.

```powershell
git clone $repo $d
```

**`git : The term 'git' is not recognized`:** git is missing from this window's PATH. Find it:

```powershell
$gp = "C:\Program Files\Git\cmd", "C:\Program Files (x86)\Git\cmd"
```
```powershell
$gp += "$env:LOCALAPPDATA\Programs\Git\cmd"
```
```powershell
$gp += (Resolve-Path "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd" -EA 0).Path
```
```powershell
$g = $gp | Where-Object { $_ -and (Test-Path "$_\git.exe") } | Select-Object -First 1
```
```powershell
$g
```

- **A folder is printed:** add it to PATH, then clone.

  ```powershell
  $env:Path += ";$g"
  ```
  ```powershell
  git clone $repo $d
  ```

- **Nothing is printed:** download the kit as a zip file. This needs no git.

  ```powershell
  [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
  ```
  ```powershell
  $zip = "$env:TEMP\sshtunnel.zip"
  ```
  ```powershell
  Invoke-WebRequest "$($repo -replace '\.git$','')/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
  ```
  ```powershell
  Expand-Archive $zip "$env:TEMP\sshtunnel-x" -Force
  ```
  ```powershell
  Move-Item "$env:TEMP\sshtunnel-x\sshtunnel-main" $d
  ```

Check the result:

```powershell
Get-ChildItem $d
```

**Expected:** `chisel.exe`, `run.cmd`, `apache-sshtunnel.conf`, `README.md` and the other kit files.

### A3. Restrict the folder to administrators

```powershell
icacls $d /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F"
```

**Expected:** `Successfully processed ... files; Failed processing 0 files`.

### A4. Create the password and the server key

```powershell
$b = New-Object byte[] 18
```
```powershell
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
```
```powershell
$pw = [Convert]::ToBase64String($b) -replace '[+/=]', 'x'
```
```powershell
$j = '{"tunnel:' + $pw + '": ["^127.0.0.1:(22|8989)$"]}'
```
```powershell
[IO.File]::WriteAllText("$d\users.json", $j)
```
```powershell
& "$d\chisel.exe" server --keygen "$d\key.pem"
```
```powershell
Get-Content "$d\users.json"
```

**Expected:** one line like `{"tunnel:Ab3xK9...": ["^127.0.0.1:(22|8989)$"]}`.

### A5. Start the tunnel server at every boot

```powershell
$act = New-ScheduledTaskAction -Execute "$d\run.cmd" -WorkingDirectory $d
```
```powershell
$trg = New-ScheduledTaskTrigger -AtStartup
```
```powershell
$usr = New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest
```
```powershell
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0
```
```powershell
$p = @{ TaskName = "SshTunnel"; Action = $act; Trigger = $trg }
```
```powershell
$p += @{ Principal = $usr; Settings = $set }
```
```powershell
Register-ScheduledTask @p
```
```powershell
Start-ScheduledTask -TaskName SshTunnel
```

Wait 5 seconds, then check it:

```powershell
curl.exe -s http://127.0.0.1:47900/health
```

**Expected:** `OK`.

```powershell
Select-String Fingerprint "$d\chisel.log"
```

**Expected:** a line ending in `server: Fingerprint` followed by a value like `U2iyQoA0c38XONp6MIXKBMmwiB/xaqwHvM/sdR8tcK4=`.

### A6. Add the forward to Apache

```powershell
$c = "$ap\conf\httpd.conf"
```
```powershell
Copy-Item $c "$c.bak-sshtunnel"
```
```powershell
Copy-Item "$d\apache-sshtunnel.conf" "$ap\conf\extra\"
```
```powershell
$inc = "Include conf/extra/apache-sshtunnel.conf"
```
```powershell
if (-not (Select-String -SimpleMatch $inc $c -Quiet)) { Add-Content $c "`r`n$inc" -Encoding Ascii }
```
```powershell
& $h -t -d $ap -f $c
```

**Expected:** `Syntax OK`.
**Any other output:** restore the backup with the line below, and do not restart Apache.

```powershell
Copy-Item "$c.bak-sshtunnel" $c -Force
```

### A7. Restart Apache

The website is unavailable for one or two seconds during the restart.

```powershell
Get-Service | Where-Object Name -match 'apache'
```

- **A service is listed** (for example `Apache2.4`): restart it with its own name.

  ```powershell
  Restart-Service Apache2.4
  ```

- **Nothing is listed:** Apache runs from the XAMPP Control Panel. Click **Stop** on the Apache row, then **Start**.

### A8. Test the forward on the server

```powershell
curl.exe -sk https://localhost/sshws/health
```

**Expected:** `OK`.

**HTML, a redirect or `Not Found` instead of `OK`:** the 443 site ignores the forward. Add it inside the 443 site:

```powershell
notepad "$ap\conf\extra\httpd-ssl.conf"
```

Find the line `</VirtualHost>` at the end of the `<VirtualHost _default_:443>` block. Paste this line directly above it, then save:

```
ProxyPass "/sshws/" "ws://127.0.0.1:47900/"
```

Run A6's `& $h -t -d $ap -f $c` line again (expected `Syntax OK`), repeat A7, then repeat A8.

### A9. Print the two lines for your PC

```powershell
$pat = 'Fingerprint (\S+)'
```
```powershell
$fp = ([regex]$pat).Match((Get-Content "$d\chisel.log" -Raw)).Groups[1].Value
```
```powershell
$pw = ([regex]'tunnel:([^"]+)').Match((Get-Content "$d\users.json")).Groups[1].Value
```
```powershell
"`$fp = '$fp'"; "`$pw = '$pw'"
```

**Expected:** two lines like these:

```
$fp = 'U2iyQoA0c38XONp6MIXKBMmwiB/xaqwHvM/sdR8tcK4='
$pw = 'Ab3xK9mQ2rT7vW1zY5cE8hJx'
```

Copy both lines. Step B3 pastes them on your PC. They are the only secrets, so keep them out of chat and email.

**Part A is complete.**

---

## Part B: Your PC

Use normal PowerShell. Administrator rights are not needed.

### B1. Test the tunnel from outside

```powershell
curl.exe -s https://fmd.scra.sc/sshws/health
```

**Expected:** `OK`.
**Anything else:** the gateway in front of the server does not pass `/sshws/` through. See Troubleshooting.

### B2. Download the kit

Skip this step if `C:\tools\sshtunnel` already exists.

```powershell
git clone https://github.com/AnonymousGhost-SC/sshtunnel.git C:\tools\sshtunnel
```

### B3. Add the SSH shortcuts

Paste the two lines that step A9 printed on the server (`$fp = '...'` and `$pw = '...'`), pressing Enter after each. Then continue:

```powershell
$url = "https://fmd.scra.sc/sshws/"
```
```powershell
$pc = "C:/tools/sshtunnel/chisel.exe client --max-retry-count 0"
```
```powershell
$pc += " --fingerprint $fp --auth tunnel:$pw $url"
```
```powershell
$cfg = "$HOME\.ssh\config"
```
```powershell
Add-Content $cfg "`r`nHost scra-ws`r`n  HostName 127.0.0.1`r`n  User SCRA.Admin" -Encoding Ascii
```
```powershell
Add-Content $cfg "  HostKeyAlias fmd.scra.sc`r`n  ProxyCommand $pc stdio:127.0.0.1:22" -Encoding Ascii
```
```powershell
Add-Content $cfg "`r`nHost scra-ws-8989`r`n  HostName 127.0.0.1`r`n  User SCRA.Admin" -Encoding Ascii
```
```powershell
Add-Content $cfg "  HostKeyAlias fmd.scra.sc`r`n  ProxyCommand $pc stdio:127.0.0.1:8989" -Encoding Ascii
```

The shortcut uses the account `SCRA.Admin`. To log in as another account, edit the `User` lines with `notepad $HOME\.ssh\config`.

### B4. Log in

```powershell
ssh scra-ws
```

**Expected on the first login:** `The authenticity of host 'fmd.scra.sc' can't be established`. Type `yes`, then enter the Windows password of `SCRA.Admin`. A server prompt appears.

```powershell
ssh scra-ws-8989
```

**Expected:** the same login, through the second sshd service on port 8989.

**Done.** Both SSH services are now reachable through port 443.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| A5 `curl` prints nothing | The tunnel server did not start | Run `Get-Content "$d\chisel.log" -Tail 20` and read the last error. Run `Start-ScheduledTask -TaskName SshTunnel` again. |
| A5 log shows `bind: Only one usage of each socket address` | Port 47900 is in use | Change `47900` to a free port in `run.cmd` and in `apache-sshtunnel.conf`, then repeat A5 to A8. |
| A6 says `Cannot load modules/mod_proxy_wstunnel.so` | Apache lacks the module | Check `Get-ChildItem "$ap\modules\mod_proxy*"`. XAMPP ships all three modules. |
| A8 works, B1 fails | The gateway blocks or rewrites `/sshws/` | Open `https://fmd.scra.sc/sshws/health` in a browser. A page from another server (not Apache) means the gateway terminates HTTPS, and it needs its own WebSocket forward for `/sshws/`. |
| B4: `connection attempts exhausted` | Wrong password or wrong fingerprint | Compare `$pw` and `$fp` with A4 and A5. Fix them with `notepad $HOME\.ssh\config`. |
| B4: `access to '127.0.0.1:22' denied` | `users.json` lists other ports | Repeat A4 without the `--keygen` line, then run the three restart lines under "Change the password". |
| B4: `REMOTE HOST IDENTIFICATION HAS CHANGED` | An old key for `fmd.scra.sc` is stored | Run `ssh-keygen -R fmd.scra.sc`, then retry. |

## Change the password

Repeat A4 (all lines except `--keygen`, which would change the fingerprint). Then restart the tunnel:

```powershell
Stop-ScheduledTask -TaskName SshTunnel
```
```powershell
Get-Process chisel -ErrorAction SilentlyContinue | Stop-Process -Force
```
```powershell
Start-ScheduledTask -TaskName SshTunnel
```

Update `--auth tunnel:...` in `$HOME\.ssh\config` on every PC that uses the tunnel.

## Remove everything

Server, PowerShell as Administrator, after running A1:

```powershell
Unregister-ScheduledTask -TaskName SshTunnel -Confirm:$false
```
```powershell
Get-Process chisel -ErrorAction SilentlyContinue | Stop-Process -Force
```
```powershell
Copy-Item "$ap\conf\httpd.conf.bak-sshtunnel" "$ap\conf\httpd.conf" -Force
```
```powershell
Remove-Item "$ap\conf\extra\apache-sshtunnel.conf"
```

Remove the `ProxyPass "/sshws/"` line from `httpd-ssl.conf` if A8 added it. Restart Apache as in A7, then delete the folder:

```powershell
Remove-Item $d -Recurse -Force
```

On the PC, delete the `Host scra-ws` and `Host scra-ws-8989` blocks from `$HOME\.ssh\config`.

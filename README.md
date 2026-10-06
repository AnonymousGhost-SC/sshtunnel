# SSH over HTTPS (chisel tunnel)

This kit carries SSH over a WebSocket on port 443. Use it when a firewall in front of the server forwards web traffic (443) and blocks every SSH port.

```
your PC: ssh scra-ws
  └ chisel client ──HTTPS 443──► Apache /sshws/ ──► chisel server 127.0.0.1:47900 ──► sshd 127.0.0.1:22
```

Two scripts do all the work:

- **`setup-server.ps1`** runs on the server. It starts the tunnel, makes it start at every boot, adds the forward to Apache, tests each part, and prints two lines for your PC.
- **`setup-client.ps1`** runs on your PC. It tests the tunnel and adds the `ssh scra-ws` shortcut.

Both scripts print `[OK]` for each finished step. A `[FAIL]` line says what went wrong and stops the script. Both scripts are safe to run again.

> **Already have `C:\sshtunnel` from the earlier guide?** Start at Step 1. It replaces the old files with the new ones.

---

## Server

Open **PowerShell as Administrator** (Start menu → type `PowerShell` → right-click → **Run as administrator**).

### Step 1. Download the kit

Copy the whole block, paste it into PowerShell, and press Enter.

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$zip = "$env:TEMP\sshtunnel.zip"
Invoke-WebRequest "https://github.com/AnonymousGhost-SC/sshtunnel/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
Expand-Archive $zip "$env:TEMP\sshtunnel-x" -Force
New-Item -ItemType Directory -Force C:\sshtunnel | Out-Null
Copy-Item "$env:TEMP\sshtunnel-x\sshtunnel-main\*" C:\sshtunnel -Recurse -Force
Get-ChildItem C:\sshtunnel -Name
```

**Expected:** a list of files that includes `setup-server.ps1` and `setup-client.ps1`.

### Step 2. Run the server setup

```powershell
powershell -ExecutionPolicy Bypass -File C:\sshtunnel\setup-server.ps1
```

**Expected:**

```
[OK]   Apache found at C:\xampp\apache
[OK]   Folder restricted to SYSTEM and Administrators
[OK]   Tunnel password created
[OK]   Server key created
[..]   Waiting for the tunnel server
[OK]   Tunnel server running on 127.0.0.1:47900, starts at every boot
[OK]   Apache config accepted
[OK]   Apache service 'Apache2.4' restarted
[..]   Checking https://localhost/sshws/health
[OK]   Apache forwards /sshws/ to the tunnel server

Server setup complete. Copy these two lines for your PC:

$fp = 'U2iyQoA0c38XONp6MIXKBMmwiB/xaqwHvM/sdR8tcK4='
$pw = 'Ab3xK9mQ2rT7vW1zY5cE8hJx'
```

**Copy the last two lines (`$fp = ...` and `$pw = ...`).** Step 4 needs them. They are the only secrets, so keep them out of chat and email.

The website is unavailable for a few seconds while Apache restarts.

---

## Your PC

Open normal PowerShell. Administrator rights are not needed.

### Step 3. Download the kit

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$zip = "$env:TEMP\sshtunnel.zip"
Invoke-WebRequest "https://github.com/AnonymousGhost-SC/sshtunnel/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
Expand-Archive $zip "$env:TEMP\sshtunnel-x" -Force
New-Item -ItemType Directory -Force C:\tools\sshtunnel | Out-Null
Copy-Item "$env:TEMP\sshtunnel-x\sshtunnel-main\*" C:\tools\sshtunnel -Recurse -Force
```

### Step 4. Run the client setup

Paste the two lines from Step 2 and press Enter. Then paste this line:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tools\sshtunnel\setup-client.ps1 -Server fmd.scra.sc -User SCRA.Admin -Name scra-ws -Fp $fp -Pw $pw
```

**Expected:**

```
[OK]   Tunnel answers at https://fmd.scra.sc/sshws/
[OK]   Port 22 answers: SSH-2.0-OpenSSH_for_Windows_9.5
[OK]   Port 8989 answers: SSH-2.0-OpenSSH_for_Windows_9.5
[OK]   Shortcuts written to C:\Users\you\.ssh\config

Setup complete. Connect with:
ssh scra-ws
ssh scra-ws-8989
```

### Step 5. Log in

```powershell
ssh scra-ws
```

On the first login, SSH asks `Are you sure you want to continue connecting`. Type `yes`, then enter the Windows password of `SCRA.Admin`.

`ssh scra-ws-8989` logs in through the second SSH service on port 8989.

---

## When a step fails

| Message | Fix |
|---|---|
| `Run PowerShell as Administrator` | Close PowerShell. Open it with **Run as administrator**, then repeat Step 2. |
| `Apache is not running` | Start Apache (XAMPP Control Panel → Apache → **Start**), then repeat Step 2. |
| `The tunnel server did not start` | Run `Get-Content C:\sshtunnel\chisel.log -Tail 20`. `bind: Only one usage of each socket address` means port 47900 is in use. Change `47900` in `run.cmd` and `apache-sshtunnel.conf`, then repeat Step 2. |
| `Apache rejected the change` | The script has already restored `httpd.conf`. The line after `Apache said:` names the problem, usually a missing `mod_proxy_wstunnel.so` in `C:\xampp\apache\modules`. |
| `https://localhost/sshws/health does not answer OK` | Read the last lines of `C:\xampp\apache\logs\error.log`. |
| Step 4: `.../sshws/health does not answer OK` | Step 2 works on the server, so the gateway in front of it blocks `/sshws/`. Open `https://fmd.scra.sc/sshws/health` in a browser. `OK` means the PC's own network blocks it. Any other page means the gateway needs a WebSocket forward for `/sshws/`. |
| Step 4: `Port 22 through the tunnel failed ... connection attempts exhausted` | The two lines from Step 2 were pasted wrongly. Paste them again, then repeat Step 4. |
| Step 4: `Port 8989 does not answer` | The second SSH service is stopped. On the server, run `Start-Service sshd_8989`. `ssh scra-ws` works without it. |
| Step 5: `REMOTE HOST IDENTIFICATION HAS CHANGED` | Run `ssh-keygen -R fmd.scra.sc`, then repeat Step 5. |
| XAMPP Control Panel shows Apache as stopped | The script restarted Apache outside the panel. The website still runs. The panel shows the right state after the next restart from the panel. |

## Change the tunnel password

On the server, as Administrator:

```powershell
Remove-Item C:\sshtunnel\users.json
powershell -ExecutionPolicy Bypass -File C:\sshtunnel\setup-server.ps1
```

Then repeat Step 4 on every PC with the two new lines.

## Remove everything

On the server, as Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File C:\sshtunnel\setup-server.ps1 -Remove
Remove-Item C:\sshtunnel -Recurse -Force
```

This stops the tunnel, removes it from startup, and returns every Apache config file to its exact earlier content.

On the PC, delete the `Host scra-ws` and `Host scra-ws-8989` blocks from `C:\Users\<you>\.ssh\config`.

---

## How it is protected

- The chisel server listens on `127.0.0.1` only. Apache is the only way in.
- Opening the tunnel needs the tunnel password, and the PC checks the server fingerprint before sending anything.
- The tunnel reaches `127.0.0.1:22` and `127.0.0.1:8989` only. Every other port is refused.
- SSH runs end to end inside the tunnel, so the normal Windows login still applies.
- `users.json` (password) and `key.pem` (server key) are created on the server and readable by SYSTEM and Administrators only. Git ignores both.

## Files

| File | Purpose |
|---|---|
| `setup-server.ps1` | Server setup, repair (`run again`) and removal (`-Remove`) |
| `setup-client.ps1` | PC setup: tests the tunnel and writes the SSH shortcuts |
| `chisel.exe` | chisel 1.12.0 for 64-bit Windows, MIT licence (`LICENSE-chisel.txt`). SHA-256 of the release zip: `600a8ad6f03bc7f6d285fd01ab6a3f8a657204adaafa5666ade9451d18df1ebc` |
| `run.cmd` | Starts the chisel server and restarts it 5 seconds after any exit |
| `apache-sshtunnel.conf` | Loads the Apache proxy modules and forwards `/sshws/` |

@echo off
rem Starts the chisel tunnel server and restarts it 5 seconds after any exit.
rem Listens on 127.0.0.1 only; Apache forwards /sshws/ to it.
cd /d "%~dp0"
:loop
chisel.exe server --host 127.0.0.1 --port 47900 --authfile users.json --keyfile key.pem >> chisel.log 2>&1
ping -n 6 127.0.0.1 >nul
goto loop

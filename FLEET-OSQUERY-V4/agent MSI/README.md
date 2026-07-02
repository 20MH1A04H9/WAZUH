# Fleet osquery Agent Install

## 1. Generate the MSI

```bash
fleetctl package \
  --type=msi \
  --fleet-url=https://<server-ip>:8080 \
  --enroll-secret=<YOUR_ENROLL_SECRET> \
  --insecure
```

Output: `/home/$USER/Desktop/fleet-osquery.msi`

> Don't commit your real enroll secret to the repo — use a placeholder like above.

## 2. Serve it over HTTP

```bash
cd /home/user/Desktop
python3 -m http.server 9999
```

## 3. Install on the target Windows host

Run PowerShell as Administrator:

```powershell
Invoke-WebRequest -Uri "http://<server-ip>:9999/fleet-osquery.msi" -OutFile "$env:TEMP\fleet-osquery.msi"

msiexec /i "$env:TEMP\fleet-osquery.msi" /quiet /l*v "$env:TEMP\fleet-install.log"
```

## 4. Stop the HTTP server

`Ctrl+C` on the build machine.

## 5. Verify enrollment

```bash
fleetctl get hosts
```

Check that the new host appears with a recent check-in time. If not, check `fleet-install.log` on the target machine.

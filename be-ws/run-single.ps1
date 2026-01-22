param(
  [int]$Port = 45444,
  [string]$HostName = "127.0.0.1",
  [string]$WsPath = "/ws/sendReq",
  [switch]$NoInstall,
  [switch]$Console
)

$ErrorActionPreference = "Stop"

$beDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexJs = Join-Path $beDir "src\index.js"
$logDir = Join-Path $beDir "logs"
$logPath = Join-Path $logDir "be-ws.log"

if (!(Test-Path $indexJs)) {
  Write-Host "ERROR: entry not found: $indexJs"
  exit 1
}

if (!(Test-Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir | Out-Null
}

function Find-BeProcess {
  $indexEsc = [regex]::Escape($indexJs)
  $rx = "(?i)be-ws[\\/]+src[\\/]+index\.js|$indexEsc"
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -and ($_.CommandLine -match $rx) }
}

$portOwnerPid = $null
try {
  $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
  $match = $conns | Where-Object { $_.LocalAddress -in @($HostName, "0.0.0.0", "::") } | Select-Object -First 1
  if ($match) { $portOwnerPid = [int]$match.OwningProcess }
}
catch {
  # Get-NetTCPConnection may not be available in some environments; ignore.
}

$existing = @(Find-BeProcess)
if (-not $existing -and $portOwnerPid) {
  try {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$portOwnerPid" -ErrorAction Stop
    if ($p -and $p.Name -ieq "node.exe") { $existing = @($p) }
  }
  catch { }
}

if ($existing.Count -gt 0) {
  $p = $existing[0]
  Write-Host "Existing BE detected (PID=$($p.ProcessId)). Forcing stop..."
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300
}
elseif ($portOwnerPid) {
  # Only kill when it looks like our BE (node).
  try {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$portOwnerPid"
    if ($p -and $p.Name -ieq "node.exe") {
      Write-Host "Port $Port is in use by node (PID=$portOwnerPid). Forcing stop..."
      Stop-Process -Id $portOwnerPid -Force -ErrorAction SilentlyContinue
      Start-Sleep -Milliseconds 300
    }
    else {
      Write-Host "ERROR: port $Port is in use by PID=$portOwnerPid (not node). Refusing to stop."
      exit 3
    }
  }
  catch {
    Write-Host "ERROR: port $Port is in use by PID=$portOwnerPid. Refusing to stop."
    exit 3
  }
}

Push-Location $beDir
try {
  if (-not $NoInstall) {
    if (!(Test-Path (Join-Path $beDir "node_modules"))) {
      Write-Host "Installing dependencies (npm i)..."
      npm i
    }
  }

  $env:PORT = "$Port"
  $env:HOST = "$HostName"
  $env:WS_PATH = "$WsPath"

  Write-Host "Starting BE..."
  Write-Host "  entry: $indexJs"
  Write-Host "  listen: ws://$HostName`:$Port$WsPath"
  Write-Host "  log: $logPath"

  if ($Console) {
    Write-Host "Console mode: showing live logs (Ctrl+C to stop)."
    Write-Host ""
    # Foreground run (keeps console open) + append to logfile.
    node "$indexJs" 2>&1 | Tee-Object -FilePath $logPath -Append
    exit 0
  }
  else {
    $cmd = "node ""$indexJs"" >> ""$logPath"" 2>&1"
    Start-Process -FilePath "cmd.exe" `
      -ArgumentList @("/c", $cmd) `
      -WorkingDirectory $beDir `
      -WindowStyle Hidden | Out-Null
  }

  Start-Sleep -Milliseconds 250

  $bePid = $null
  for ($i = 0; $i -lt 20; $i++) {
    $started = @(Find-BeProcess)
    if ($started.Count -gt 0) { $bePid = $started[0].ProcessId; break }
    try {
      $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
      $match = $conns | Where-Object { $_.LocalAddress -in @($HostName, "0.0.0.0", "::") } | Select-Object -First 1
      if ($match) { $bePid = [int]$match.OwningProcess; break }
    }
    catch { }
    Start-Sleep -Milliseconds 150
  }

  if ($bePid) {
    Write-Host "BE started (PID=$bePid)."
    exit 0
  }

  Write-Host "WARNING: BE process not detected. Check log: $logPath"
  exit 2
}
finally {
  Pop-Location
}


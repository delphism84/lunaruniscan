param(
  [string]$SdkRoot = "C:\Users\rc\AppData\Local\Android\Sdk",
  [string]$AvdName = "uniscan_api33",
  [string]$SystemImage = "system-images;android-33;google_apis;x86_64",
  [switch]$SkipInstall
)

Write-Host "== FE Android setup & run =="

$projectDir = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
Set-Location $projectDir

function Ensure-Dir($p) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Ensure-AndroidCmdlineTools {
  $cmdlineDir = Join-Path $SdkRoot "cmdline-tools\latest"
  if (Test-Path (Join-Path $cmdlineDir "bin\sdkmanager.bat")) { return }
  Write-Host "Downloading Android cmdline-tools..."
  Ensure-Dir (Join-Path $SdkRoot "cmdline-tools")
  $zip = Join-Path $env:TEMP "cmdline-tools.zip"
  $url = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
  Invoke-WebRequest -Uri $url -OutFile $zip
  Ensure-Dir $cmdlineDir
  Expand-Archive -Path $zip -DestinationPath $cmdlineDir -Force
}

function Set-AndroidEnv {
  $env:ANDROID_HOME = $SdkRoot
  $env:ANDROID_SDK_ROOT = $SdkRoot
  $env:PATH = ($env:PATH + ";$SdkRoot\platform-tools;$SdkRoot\emulator;$SdkRoot\cmdline-tools\latest\bin")
}

function Ensure-Pkgs {
  if ($SkipInstall) { return }
  Write-Host "Installing Android SDK packages..."
  & sdkmanager --sdk_root="$SdkRoot" "platform-tools" "emulator" "platforms;android-33" "build-tools;33.0.2" $SystemImage
  echo y | & sdkmanager --licenses --sdk_root="$SdkRoot"
}

function Ensure-Avd {
  $avdHome = Join-Path $env:USERPROFILE ".android\avd"
  Ensure-Dir $avdHome
  $ini = Join-Path $avdHome "$AvdName.avd\config.ini"
  if (Test-Path $ini) { return }
  Write-Host "Creating AVD $AvdName ..."
  echo no | & avdmanager create avd -n $AvdName -k $SystemImage --device "pixel_5" --sdcard 2048M
}

function Ensure-LocalProps {
  $local = Join-Path $projectDir "android\local.properties"
  $content = @"
sdk.dir=$SdkRoot
"@
  Set-Content -Path $local -Value $content -Encoding ascii
}

function Start-Emulator {
  Write-Host "Starting emulator $AvdName ..."
  Start-Process -FilePath "emulator" -ArgumentList "-avd $AvdName -netdelay none -netspeed full -no-snapshot -no-boot-anim" -WindowStyle Minimized
  Write-Host "Waiting for device..."
  & adb wait-for-device
  for ($i=0; $i -lt 90; $i++) {
    $booted = (& adb shell getprop sys.boot_completed 2>$null).Trim()
    if ($booted -eq "1") { break }
    Start-Sleep -Seconds 2
  }
  Write-Host "Device is ready."
}

# Steps
Ensure-Dir $SdkRoot
Ensure-AndroidCmdlineTools
Set-AndroidEnv
Ensure-Pkgs
Ensure-Avd
Ensure-LocalProps

Write-Host "Flutter prepare..."
& flutter pub get

Start-Emulator

Write-Host "Running app on emulator..."
& flutter run -d emulator-5554 -t lib/main.dart



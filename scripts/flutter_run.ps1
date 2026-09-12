<#
.SYNOPSIS
    로컬 백엔드를 물린 채로 안드로이드 기기에 앱을 띄운다.

.DESCRIPTION
    실기기에서 그냥 `flutter run`을 하면 로컬 서버에 닿지 못하고 30초 뒤
    connectionTimeout이 난다. 앱의 디버그 기본값(frontend/app/lib/config/app_config.dart)이
    10.0.2.2인데, 그건 에뮬레이터의 가상 NAT가 호스트 루프백으로 넘겨주는 별칭이라
    실기기에는 그런 주소가 없기 때문이다.

    그래서 이 스크립트가 두 가지를 대신한다:
      1. adb reverse — 기기의 127.0.0.1:PORT 를 USB로 PC의 같은 포트에 연결한다.
      2. --dart-define=API_BASE_URL — 앱이 그 127.0.0.1 을 보게 한다.

    PC의 LAN IP를 알 필요도, 방화벽을 열 필요도 없어서 팀원 누구나 그대로 쓸 수 있다.
    adb reverse는 에뮬레이터도 지원하므로 기기 종류를 가리지 않는다.

    adb reverse는 기기를 다시 꽂거나 재부팅하면 풀린다. 그래서 `flutter run`을 직접
    치지 않고 매번 이 스크립트로 실행한다 — 실행할 때마다 다시 걸어준다.

    iOS 실기기는 대상이 아니다(adb는 안드로이드 전용). iOS 실기기는 PC의 LAN IP를
    --dart-define으로 직접 넘겨야 한다.

    서버를 먼저 띄워둘 것: .\scripts\local_docker_start.ps1 up

.EXAMPLE
    .\scripts\flutter_run.ps1
    .\scripts\flutter_run.ps1 -DeviceId R3CT30ABCDE
    .\scripts\flutter_run.ps1 -Port 8000 --verbose
#>

[CmdletBinding()]
param(
    [int]$Port = 8000,

    # 기기가 여러 대 붙어 있을 때 고른다. adb reverse는 대상을 하나로 특정해야 한다.
    [string]$DeviceId,

    # 나머지는 flutter run 에 그대로 넘긴다.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $RepoRoot 'frontend\app'

# adb는 PATH에 없는 경우가 흔하다(안드로이드 스튜디오가 PATH를 안 건드린다).
# 그래서 SDK 위치를 직접 뒤진다.
function Resolve-Adb {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $roots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") |
             Where-Object { $_ }

    foreach ($root in $roots) {
        $candidate = Join-Path $root 'platform-tools\adb.exe'
        if (Test-Path $candidate) { return $candidate }
    }

    throw 'adb를 찾지 못했어요. 안드로이드 SDK를 설치하고 ANDROID_HOME을 설정하거나, platform-tools를 PATH에 넣어주세요.'
}

# `adb devices` 출력에서 상태가 device인 것만 시리얼로 뽑는다.
# (unauthorized/offline은 reverse가 안 되므로 제외한다 — 여기서 걸러야 원인이 분명해진다.)
function Get-AttachedDevices {
    param([string]$Adb)

    & $Adb devices |
        Select-Object -Skip 1 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '\sdevice$' } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

# 서버가 안 떠 있으면 앱은 결국 또 타임아웃을 볼 뿐이다. 여기서 미리 알려준다.
function Test-LocalPort {
    param([int]$Port)

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        return $client.ConnectAsync('127.0.0.1', $Port).Wait(500) -and $client.Connected
    }
    catch { return $false }
    finally { $client.Dispose() }
}

$adb = Resolve-Adb
$devices = @(Get-AttachedDevices -Adb $adb)

if ($devices.Count -eq 0) {
    throw '연결된 안드로이드 기기가 없어요. USB 디버깅을 켜고, 기기 화면의 "USB 디버깅을 허용하시겠습니까?"를 승인했는지 확인해주세요.'
}

if ($DeviceId) {
    if ($devices -notcontains $DeviceId) {
        throw ("'{0}' 기기를 찾지 못했어요. 붙어 있는 기기: {1}" -f $DeviceId, ($devices -join ', '))
    }
}
elseif ($devices.Count -gt 1) {
    throw ("기기가 여러 대 붙어 있어요: {0}{1}  -DeviceId 로 하나를 골라주세요." -f ($devices -join ', '), [Environment]::NewLine)
}
else {
    $DeviceId = $devices[0]
}

if (-not (Test-LocalPort -Port $Port)) {
    Write-Host ("경고: 127.0.0.1:{0} 에 아무것도 안 떠 있어요. 서버를 먼저 띄우세요 — .\scripts\local_docker_start.ps1 up" -f $Port) -ForegroundColor Yellow
}

& $adb -s $DeviceId reverse ("tcp:{0}" -f $Port) ("tcp:{0}" -f $Port)
if ($LASTEXITCODE -ne 0) { throw "adb reverse 실패 (exit $LASTEXITCODE)" }
Write-Host ("▶ adb reverse: {0} 의 127.0.0.1:{1} → 이 PC의 {1}" -f $DeviceId, $Port) -ForegroundColor DarkGray

$flutterArgs = @('run', '-d', $DeviceId, "--dart-define=API_BASE_URL=http://127.0.0.1:$Port")
if ($Rest) { $flutterArgs += $Rest }

Write-Host ("▶ flutter {0}" -f ($flutterArgs -join ' ')) -ForegroundColor DarkGray

Push-Location $AppDir
try { & flutter @flutterArgs }
finally { Pop-Location }

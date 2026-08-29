<#
.SYNOPSIS
    백엔드 개발 환경 조작 스크립트.

.DESCRIPTION
    DB와 API를 도커로 함께 띄운다. up/rebuild가 컨테이너를 올리기 전에
    마이그레이션을 먼저 실행하므로 따로 챙길 필요는 없다.

    엔트리포인트가 아니라 여기서 도는 이유는 운영과 조건을 맞추기 위해서다 —
    운영(Cloud Run)은 마이그레이션을 배포 파이프라인의 별도 스텝으로 뺐다
    (cloudbuild.yaml, docs/cicd.md). 기동 경로에 남겨두면 실패했을 때
    컨테이너가 재시작만 반복한다.

.EXAMPLE
    .\scripts\dev.ps1 up          # DB + API 기동 (백그라운드)
    .\scripts\dev.ps1 logs        # 로그 따라가기
    .\scripts\dev.ps1 migrate     # 스키마를 head까지 올리기
    .\scripts\dev.ps1 revision "add course tags"
    .\scripts\dev.ps1 seed        # courses/ 의 GPX를 API로 업로드
    .\scripts\dev.ps1 test
    .\scripts\dev.ps1 down
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'down', 'restart', 'rebuild', 'logs', 'migrate', 'revision',
                 'psql', 'shell', 'test', 'seed', 'status')]
    [string]$Command = 'up',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Compose = Join-Path $RepoRoot 'infra\docker-compose.yml'

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    & docker compose -f $Compose @ComposeArgs
    if ($LASTEXITCODE -ne 0) { throw "docker compose $($ComposeArgs -join ' ') 실패 (exit $LASTEXITCODE)" }
}

# 컨테이너 안에서 일회성 명령을 돌린다. api가 떠 있으면 exec, 아니면 run.
function Invoke-Api {
    param([string[]]$ApiArgs)

    $running = (& docker compose -f $Compose ps --status running --services) -split "`n" |
               ForEach-Object { $_.Trim() }

    if ($running -contains 'api') {
        Invoke-Compose (@('exec', 'api') + $ApiArgs)
    }
    else {
        # api가 안 떠 있을 때(그리고 스키마가 어긋나 못 뜰 때)도 돌아야 하므로
        # 일회용 컨테이너를 쓴다.
        Invoke-Compose (@('run', '--rm', '--entrypoint', '', 'api') + $ApiArgs)
    }
}

# 이미지를 만들고, 스키마를 head까지 올린 뒤, 컨테이너를 띄운다.
# 순서가 중요하다 — 스키마가 어긋나면 app/schema_guard.py가 기동을 거부한다.
function Start-Stack {
    param([string[]]$UpArgs)

    Invoke-Compose @('build')
    Invoke-Api @('alembic', 'upgrade', 'head')
    Invoke-Compose (@('up', '-d') + $UpArgs)

    Write-Host ''
    Write-Host '  API   http://localhost:8000' -ForegroundColor Green
    Write-Host '  docs  http://localhost:8000/docs' -ForegroundColor Green
    Write-Host '  로그  .\scripts\dev.ps1 logs' -ForegroundColor DarkGray
}

switch ($Command) {
    'up'      { Start-Stack @() }
    'down'    { Invoke-Compose @('down') }
    'restart' { Invoke-Compose @('restart', 'api') }
    'rebuild' { Start-Stack @('--force-recreate') }
    'logs'    { Invoke-Compose @('logs', '-f', '--tail', '100') }
    'status'  { Invoke-Compose @('ps') }

    'migrate' { Invoke-Api @('alembic', 'upgrade', 'head') }

    'revision' {
        if (-not $Rest) { throw '메시지가 필요해요. 예: .\scripts\dev.ps1 revision "add course tags"' }
        Invoke-Api (@('alembic', 'revision', '--autogenerate', '-m') + $Rest)
        Write-Host '생성된 마이그레이션을 반드시 눈으로 확인하세요. autogenerate는 완벽하지 않습니다.' -ForegroundColor Yellow
    }

    'psql'  { Invoke-Compose @('exec', 'db', 'psql', '-U', 'runner', '-d', 'runner_jeju') }
    'shell' { Invoke-Compose @('exec', 'api', 'bash') }
    'test'  { Invoke-Api @('pytest', '-q') }

    'seed'  { Invoke-Api (@('python', '-m', 'tools.push_courses') + $Rest) }
}

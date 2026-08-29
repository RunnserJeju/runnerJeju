# CI/CD — live 브랜치 자동 배포

`main`은 개발, `live`는 배포다. **`live`에 푸시되는 순간 Cloud Build가 테스트 →
이미지 빌드 → 마이그레이션 → Cloud Run 배포를 자동으로 돌린다.** 파이프라인 정의는
저장소 루트의 [`cloudbuild.yaml`](../cloudbuild.yaml)에 있다.

이 문서는 **최초 1회 설정**과 **평소 사용법·롤백**을 담는다. 왜 이렇게 배포하는지
(pooler, 시크릿, 스케일)는 [`deployment.md`](deployment.md)를 본다.

## 전체 그림

```
main (개발)  ──PR──▶  live (배포)
                        │ push
                        ▼
                  Cloud Build 트리거
                        │
      ┌─────────────────┼─────────────────┐
      │ 1. pytest                          │  실패하면 여기서 멈춤 —
      │ 2. 이미지 빌드 → Artifact Registry │  라이브는 이전 리비전 그대로
      │    태그: <커밋SHA> + live           │
      │ 3. alembic upgrade head (Run Job)  │
      │ 4. gcloud run deploy               │
      └────────────────────────────────────┘
                        ▼
              Cloud Run: runners-jeju-api
```

**왜 마이그레이션이 별도 스텝인가.** 예전엔 컨테이너 엔트리포인트가 부팅할 때마다
`alembic upgrade head`를 돌렸다. 그러면 마이그레이션이 실패했을 때 새 컨테이너가
아예 못 뜨고 재시작만 반복해 정상 인스턴스가 남지 않는다. 밖으로 빼면 실패가
**배포 이전**에 드러나고 기존 리비전이 트래픽을 계속 받는다. 대신 빠뜨렸을 때를
대비해 [`schema_guard`](../server/app/schema_guard.py)가 부팅 시 검증만 한다.

---

# 최초 1회 설정

아래는 `runners-jeju-505808` 프로젝트 기준이다. **이름이 같은 `runners-jeju`
프로젝트가 따로 있는데 그건 빈 프로젝트다. 헷갈리지 않는다.**

```powershell
gcloud config set project runners-jeju-505808
```

## 1. KAKAO 키를 Secret Manager에 넣는다 — ✅ 완료 (2026-08-30)

`kakao-key` 시크릿이 생성됐고 런타임 계정에 접근 권한도 부여됐다. 아래는 키를
교체하거나 다시 만들 때를 위한 기록이다. 값은 `infra/.env`의
`KAKAO_REST_API_KEY`와 같다.

> 키를 교체할 땐 새로 만들지 말고 버전을 추가한다:
> `gcloud secrets versions add kakao-key --data-file=kakao.txt`
> (`cloudbuild.yaml`이 `:latest`를 참조하므로 다음 배포부터 새 값이 적용된다.)

```powershell
# 파일로 잠깐 떨궜다 지운다. 명령 히스토리에 키가 남지 않게.
"<REST API 키>" | Out-File -NoNewline -Encoding ascii kakao.txt
gcloud secrets create kakao-key --data-file=kakao.txt
Remove-Item kakao.txt
```

런타임 서비스 계정이 읽을 수 있게 권한을 준다(기존 3개 시크릿과 같은 계정).

```powershell
gcloud secrets add-iam-policy-binding kakao-key `
  --member="serviceAccount:1090471391353-compute@developer.gserviceaccount.com" `
  --role="roles/secretmanager.secretAccessor"
```

## 2. 배포 전용 서비스 계정을 만든다

Cloud Build 기본 계정을 쓰지 않고 전용 계정을 두는 이유는 권한을 배포에 필요한
만큼만 주기 위해서다.

```powershell
gcloud iam service-accounts create cicd-deployer --display-name="Cloud Build deployer"
```

```powershell
$SA = "cicd-deployer@runners-jeju-505808.iam.gserviceaccount.com"

# Cloud Run 서비스/Job 생성·수정
gcloud projects add-iam-policy-binding runners-jeju-505808 `
  --member="serviceAccount:$SA" --role="roles/run.admin"

# 이미지 push
gcloud projects add-iam-policy-binding runners-jeju-505808 `
  --member="serviceAccount:$SA" --role="roles/artifactregistry.writer"

# 빌드 로그 기록 (cloudbuild.yaml의 logging: CLOUD_LOGGING_ONLY)
gcloud projects add-iam-policy-binding runners-jeju-505808 `
  --member="serviceAccount:$SA" --role="roles/logging.logWriter"

# 배포한 서비스가 "런타임 계정"으로 돌게 하려면 그 계정을 쓸 권한이 필요하다.
gcloud iam service-accounts add-iam-policy-binding `
  1090471391353-compute@developer.gserviceaccount.com `
  --member="serviceAccount:$SA" --role="roles/iam.serviceAccountUser"
```

> 위 4개는 **최소 권한**이다. 그래도 빌드가 권한 문제로 막히면(소스 스테이징 등)
> `roles/cloudbuild.builds.builder`를 한 번 더 붙이고 다시 좁혀나간다.

## 3. GitHub 저장소를 Cloud Build에 연결한다 (브라우저)

**이 단계만 CLI로 안 되고 콘솔에서 클릭해야 한다.** GitHub App을 설치하는 절차라
`RunnserJeju` 조직에 앱을 설치할 권한(오너/관리자)이 필요하다.

1. https://console.cloud.google.com/cloud-build/triggers?project=runners-jeju-505808
2. **저장소 연결** → GitHub 선택 → GitHub 인증
3. `RunnserJeju/runnerJeju` 선택 후 연결

> 리전을 물으면 `asia-northeast3`를 고르고, 목록에 없으면 `global`로 둔다.
> 트리거 리전은 배포될 Cloud Run 리전과 무관하다.

## 4. 트리거를 만든다

연결이 끝났으면 CLI로 만들 수 있다.

```powershell
gcloud builds triggers create github `
  --name=deploy-live `
  --repo-owner=RunnserJeju --repo-name=runnerJeju `
  --branch-pattern="^live$" `
  --build-config=cloudbuild.yaml `
  --service-account="projects/runners-jeju-505808/serviceAccounts/cicd-deployer@runners-jeju-505808.iam.gserviceaccount.com"
```

`--branch-pattern`이 정규식이라 `^live$`로 정확히 묶는다. `live`만 매칭되고
`live-test` 같은 브랜치는 안 걸린다.

## 5. live 브랜치를 만든다

```powershell
git switch -c live
git push -u origin live
```

GitHub에서 `live` 브랜치 보호 규칙을 켜두면 좋다 — **직접 푸시 금지, PR로만 병합.**
실수로 검증 안 된 커밋이 라이브로 나가는 걸 막는다.

## 6. 첫 배포

`live`를 푸시한 순간 트리거가 이미 돌았을 것이다. 확인:

```powershell
gcloud builds list --limit 3
gcloud run services describe runners-jeju-api --region asia-northeast3 --format="value(status.latestReadyRevisionName)"
```

---

# 평소 사용법

## 배포하기

```powershell
git switch live
git merge main      # 또는 GitHub에서 main → live PR
git push
```

끝이다. 진행 상황은 콘솔의 Cloud Build > 기록에서 본다.

## 지금 라이브에 어떤 커밋이 떠 있나

```powershell
gcloud run services describe runners-jeju-api --region asia-northeast3 `
  --format="value(spec.template.spec.containers[0].image)"
```

이미지 태그가 커밋 SHA다. `git show <SHA>`로 바로 확인할 수 있다.

## 롤백

리비전 목록에서 되돌릴 리비전을 고른다.

```powershell
gcloud run revisions list --service runners-jeju-api --region asia-northeast3

gcloud run services update-traffic runners-jeju-api --region asia-northeast3 `
  --to-revisions=<되돌릴-리비전>=100
```

> **주의: 코드는 즉시 돌아가지만 DB 스키마는 안 돌아온다.** 마이그레이션이 컬럼을
> 지웠거나 이름을 바꿨다면 옛 코드가 그 스키마에서 깨질 수 있다. 그래서
> 마이그레이션은 되도록 **덧붙이는 방향(컬럼 추가·nullable)** 으로 쓰고, 지우는
> 변경은 코드가 안정된 다음 배포에서 분리한다.

## 마이그레이션만 다시 돌리기

파이프라인 밖에서 손으로 돌려야 할 때:

```powershell
gcloud run jobs execute runners-jeju-api-migrate --region asia-northeast3 --wait
```

---

# 막혔을 때

| 증상 | 원인 |
| --- | --- |
| 빌드가 test 스텝에서 실패 | 진짜 테스트가 깨진 것. `.\scripts\dev.ps1 test`로 로컬 재현 |
| `PERMISSION_DENIED` (run/artifactregistry) | 2번 권한 부여 누락. `gcloud projects get-iam-policy`로 확인 |
| migrate 스텝에서 실패 | 마이그레이션 자체 문제. **라이브는 안 바뀌었다.** Job 로그를 본다 |
| 배포 후 기동 실패, `SchemaOutOfDateError` | migrate 스텝이 건너뛰어졌다. 새 마이그레이션 파일이 이미지에 들어갔는지 확인 |
| 배포는 됐는데 좌표 변환이 502 | `kakao-key` 시크릿 누락 (1번) |
| 푸시했는데 아무 일도 안 일어남 | 트리거 브랜치 패턴 확인. `gcloud builds triggers list` |

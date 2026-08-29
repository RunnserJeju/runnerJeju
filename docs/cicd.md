# CI/CD — live 브랜치 자동 배포

`main`은 개발, `live`는 배포다. **`live`에 푸시되는 순간 Cloud Build가 테스트 →
이미지 빌드 → 마이그레이션 → Cloud Run 배포를 자동으로 돌린다.** 파이프라인 정의는
저장소 루트의 [`cloudbuild.yaml`](../cloudbuild.yaml)에 있다.

설정은 **2026-08-30에 끝났다.** 아래 "설정 기록"은 다시 만들거나 다른 환경에 복제할
때를 위한 것이고, 평소에는 "사용법"부터 보면 된다. 왜 이렇게 배포하는지(pooler,
시크릿, 스케일)는 [`deployment.md`](deployment.md)에 있다.

## 전체 그림

```
main (개발)  ──PR/merge──▶  live (배포)
                              │ push
                              ▼
                     Cloud Build 트리거 "deploy-live"
                              │
      ┌───────────────────────┼───────────────────────┐
      │ 1. pytest                                      │  실패하면 여기서 멈춤 —
      │ 2. 이미지 빌드 → Artifact Registry             │  라이브는 이전 리비전 그대로
      │    태그: <커밋SHA> + live                       │
      │ 3. alembic upgrade head (Cloud Run Job)        │
      │ 4. gcloud run deploy                           │
      └────────────────────────────────────────────────┘
                              ▼
                  Cloud Run: runners-jeju-api (asia-northeast3)
```

**왜 마이그레이션이 별도 스텝인가.** 예전엔 컨테이너 엔트리포인트가 부팅할 때마다
`alembic upgrade head`를 돌렸다. 그러면 마이그레이션이 실패했을 때 새 컨테이너가
아예 못 뜨고 재시작만 반복해 정상 인스턴스가 남지 않는다. 밖으로 빼면 실패가
**배포 이전**에 드러나고 기존 리비전이 트래픽을 계속 받는다. 대신 빠뜨렸을 때를
대비해 [`schema_guard`](../server/app/schema_guard.py)가 부팅 시 검증만 한다.

---

# 사용법

## 배포하기

```powershell
git switch live
git merge main      # 또는 GitHub에서 main → live PR
git push            # ← 이게 배포다
```

진행 상황은 콘솔의 Cloud Build > 기록, 또는:

```powershell
gcloud builds list --limit 3
```

## 지금 라이브에 어떤 커밋이 떠 있나

```powershell
gcloud run services describe runners-jeju-api --region asia-northeast3 `
  --format="value(spec.template.spec.containers[0].image)"
```

이미지 태그가 곧 커밋 SHA다. `git show <SHA>`로 바로 확인할 수 있다.

## 롤백

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

```powershell
gcloud run jobs execute runners-jeju-api-migrate --region asia-northeast3 --wait
```

## 커밋 없이 지금 코드로 다시 배포

```powershell
gcloud builds triggers run deploy-live --branch=live
```

---

# 막혔을 때

| 증상 | 원인 |
| --- | --- |
| test 스텝에서 실패 | 진짜 테스트가 깨진 것. `.\scripts\dev.ps1 test`로 로컬 재현 |
| migrate 스텝에서 실패 | 마이그레이션 자체 문제. **라이브는 안 바뀌었다.** Job 실행 로그를 본다 |
| 배포 후 `SchemaOutOfDateError`로 기동 실패 | migrate 스텝이 건너뛰어졌다. 새 마이그레이션 파일이 이미지에 들어갔는지 확인 |
| 좌표 변환(`/admin/geo/geocode`)이 502 | `kakao-key` 시크릿 문제 |
| 푸시했는데 아무 일도 안 일어남 | `gcloud builds triggers list`로 브랜치 패턴 확인 |
| `PERMISSION_DENIED` | 빌드 계정 권한. 아래 설정 기록 2번 |

> ⚠️ **Cloud Run 콘솔의 "지속적 배포 설정" 마법사를 다시 쓰지 않는다.**
> 그 마법사는 `cloudbuild.yaml`을 **무시하고** 콘솔에 박힌 인라인 설정으로 트리거를
> 만든다. 실제로 처음에 그렇게 만들어져서 `main`을 감시하고, 테스트·마이그레이션·
> 시크릿이 전부 빠진 채로, Dockerfile 경로에 역슬래시(`server\Dockerfile`)가 들어가
> 빌드가 실패했다. 트리거는 아래 4번의 CLI 명령으로만 만든다.

---

# 설정 기록 (2026-08-30 완료)

`runners-jeju-505808` 프로젝트 기준이다. **이름이 같은 `runners-jeju` 프로젝트가
따로 있는데 그건 빈 프로젝트다. 헷갈리지 않는다.**

```powershell
gcloud config set project runners-jeju-505808
```

## 1. KAKAO 키를 Secret Manager에 ✅

이 키가 없으면 코스 등록의 주차장/화장실 주소→좌표 변환이 502를 낸다. 값은
`infra/.env`의 `KAKAO_REST_API_KEY`와 같다.

```powershell
"<REST API 키>" | Out-File -NoNewline -Encoding ascii kakao.txt
gcloud secrets create kakao-key --data-file=kakao.txt
Remove-Item kakao.txt

gcloud secrets add-iam-policy-binding kakao-key `
  --member="serviceAccount:1090471391353-compute@developer.gserviceaccount.com" `
  --role="roles/secretmanager.secretAccessor"
```

> 키를 **교체**할 땐 새로 만들지 말고 버전을 추가한다:
> `gcloud secrets versions add kakao-key --data-file=kakao.txt`
> (`cloudbuild.yaml`이 `:latest`를 참조하므로 다음 배포부터 적용된다.)

이로써 운영 시크릿은 `db-url`, `jwt-key`, `sb-key`, `kakao-key` 4개다.

## 2. 빌드 계정 ✅

**기본 compute 계정을 그대로 쓴다** — `1090471391353-compute@developer.gserviceaccount.com`.
Cloud Run 마법사가 이미 필요한 역할을 다 붙여놨고, 확인해보니 아래 4개가 있다.

| 역할 | 왜 필요한가 |
| --- | --- |
| `roles/run.admin` | Cloud Run 서비스·Job 생성/수정 |
| `roles/artifactregistry.writer` | 이미지 push |
| `roles/logging.logWriter` | `logging: CLOUD_LOGGING_ONLY` |
| `roles/iam.serviceAccountUser` | 배포한 서비스를 런타임 계정으로 실행 |

```powershell
# 현재 역할 확인
gcloud projects get-iam-policy runners-jeju-505808 `
  --flatten="bindings[].members" `
  --filter="bindings.members:1090471391353-compute@developer.gserviceaccount.com" `
  --format="value(bindings.role)"
```

> 이 계정은 **빌드 계정이자 서버 런타임 계정**이고 `roles/editor`도 갖고 있어서
> 권한이 넓다. 팀이 커지거나 외부 기여자가 생기면 배포 전용 계정
> (`cicd-deployer`)을 따로 만들어 위 4개만 주고 트리거의 `--service-account`를
> 바꾸는 게 낫다. 지금 규모에선 계정을 늘리는 비용이 더 크다고 판단했다.

## 3. GitHub 저장소 연결 ✅ (브라우저)

**이 단계만 CLI로 안 된다.** GitHub App 설치 절차라 `RunnserJeju` 조직에 앱을 설치할
권한(오너/관리자)이 필요하다.

1. https://console.cloud.google.com/cloud-build/triggers?project=runners-jeju-505808
2. **저장소 연결** → GitHub 선택 → 인증 → `RunnserJeju/runnerJeju` 연결

여기까지만 하고 **트리거는 이 화면에서 만들지 않는다** (위 ⚠️ 참고). 다음 단계로 간다.

## 4. 트리거 생성 ✅

```powershell
gcloud builds triggers create github `
  --name=deploy-live `
  --description="live 브랜치 푸시 시 테스트-빌드-마이그레이션-배포 (cloudbuild.yaml)" `
  --repo-owner=RunnserJeju --repo-name=runnerJeju `
  --branch-pattern="^live$" `
  --build-config=cloudbuild.yaml `
  --service-account="projects/runners-jeju-505808/serviceAccounts/1090471391353-compute@developer.gserviceaccount.com"
```

`--branch-pattern`이 정규식이라 `^live$`로 정확히 묶는다. `live-test` 같은 브랜치는
안 걸린다.

## 5. live 브랜치 ✅

```powershell
git switch -c live
git push -u origin live
```

GitHub에서 `live` 브랜치 보호 규칙을 켜두면 좋다 — **직접 푸시 금지, PR로만 병합.**
검증 안 된 커밋이 실수로 라이브에 나가는 걸 막는다. (아직 안 걸어둠)

## 6. 첫 배포 ✅

커밋 `0c88336` → 리비전 `runners-jeju-api-00004-nk5`. 이 배포로 13일 밀려 있던
찜(`/favorites`)·운영진(`/admin/*`)·좌표 변환 API가 라이브에 올라갔고,
마이그레이션 `0009`·`0010`이 적용됐다.

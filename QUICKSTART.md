# Harbor 오프라인 설치 빠른 시작 가이드

## 한 줄 요약

Harbor를 완전 오프라인 RHEL 9.6 환경에서 nerdctl/containerd로 설치하고 자동 테스트까지 완료하는 가이드입니다.

## 전체 워크플로우 (3단계)

### 1단계: 온라인 시스템에서 패키지 다운로드

```bash
# 환경 설정
cp env.example .env
vi .env  # HARBOR_HOSTNAME, ENABLE_HTTPS 등 설정

# 패키지 다운로드 + 패키징
make quick-online

# (선택) HTTPS 사용 시 인증서 생성
make generate-certs
```

**생성되는 파일:**
- `harbor-offline-rhel96-YYYYMMDD.tar.gz` - Harbor 설치 패키지
- `harbor-certs-<hostname>.tar.gz` - HTTPS 인증서 (선택)

### 2단계: 오프라인 시스템으로 파일 전송

```bash
# USB 또는 SCP로 전송
scp harbor-offline-rhel96-*.tar.gz user@offline-server:/root/
```

### 3단계: 오프라인 시스템에서 설치 및 테스트

```bash
# 패키지 압축 해제 및 설치
sudo make quick-offline

# Harbor 설정
cd /opt/harbor
sudo vi harbor.yml  # hostname, 비밀번호 확인
sudo ./install.sh

# 자동 테스트 실행
cd ~/harbor-offline-install
make harbor-test
```

## HTTP vs HTTPS 선택

### HTTP 모드 (기본, 개발/테스트용)

```bash
# .env 설정
ENABLE_HTTPS=false
HARBOR_HOSTNAME=192.168.135.96

# 설치 후 containerd 설정
sudo make configure-containerd

# 테스트
make harbor-test
```

### HTTPS 모드 (운영 권장)

```bash
# .env 설정
ENABLE_HTTPS=true
HARBOR_HOSTNAME=harbor.example.com
CERT_ADDITIONAL_SANS=192.168.135.96,harbor-prod.example.com

# 온라인 시스템에서 인증서 생성
make generate-certs

# 오프라인 시스템에서 인증서 설치
tar -xzf harbor-certs-*.tar.gz
sudo make install-certs

# containerd에 CA 인증서 등록
sudo make configure-containerd

# 테스트
make harbor-test
```

## 자동 테스트 내용

`make harbor-test` 실행 시 다음 항목을 자동으로 검증합니다:

1. ✓ Harbor 설치 디렉토리 존재 확인
2. ✓ Harbor 컨테이너 상태 (9개 running)
3. ✓ Harbor 웹 UI 접근 (HTTP/HTTPS)
4. ✓ Harbor API 인증 (admin 계정)
5. ✓ 프로젝트 목록 조회
6. ✓ 테스트 프로젝트 생성
7. ✓ 생성된 프로젝트 조회
8. ✓ 레지스트리 로그인 (선택)
9. ✓ Harbor 로그 접근 가능 여부
10. ✓ 디스크 공간 확인

## 주요 명령어 요약

```bash
# Harbor 서비스 관리
make harbor-start       # Harbor 시작
make harbor-stop        # Harbor 중지
make harbor-restart     # Harbor 재시작
make harbor-status      # 상태 확인
make harbor-logs        # 로그 확인 (실시간)
make harbor-test        # 자동 테스트

# containerd 설정
sudo make configure-containerd  # Harbor 레지스트리 설정

# 인증서 관리
make generate-certs     # 인증서 생성
make install-certs      # 인증서 설치
make add-ca            # CA 인증서 시스템 등록
```

## 접속 정보

설치 완료 후:
- **웹 UI**: http://192.168.135.96 또는 https://harbor.example.com
- **사용자명**: admin
- **비밀번호**: Harbor12345 (변경 권장)

## 문제 해결

### Harbor 컨테이너가 시작되지 않을 때
```bash
cd /opt/harbor
nerdctl compose logs        # 로그 확인
nerdctl compose restart     # 재시작
```

### API 502 에러 발생 시
```bash
# Harbor 서비스 재시작
cd /opt/harbor
nerdctl compose restart
sleep 10  # 서비스 안정화 대기
```

### nerdctl 로그인 실패 시
```bash
# containerd 설정 확인
sudo make configure-containerd

# 설정 확인
ls -la /etc/containerd/certs.d/
cat /etc/containerd/certs.d/<harbor-host>/hosts.toml
```

## 다음 단계

1. **프로젝트 생성**: 웹 UI에서 새 프로젝트 생성
2. **이미지 Push 테스트**:
   ```bash
   nerdctl pull nginx:latest
   nerdctl tag nginx:latest 192.168.135.96/library/nginx:test
   nerdctl push 192.168.135.96/library/nginx:test
   ```
3. **Kubernetes 연동**: [README-K8S.md](README-K8S.md) 참조

## 참고 문서

- [README-KR.md](README-KR.md) - 상세 설치 가이드
- [CLAUDE.md](CLAUDE.md) - 개발자 가이드
- [SUMMARY-KR.md](SUMMARY-KR.md) - 프로젝트 요약

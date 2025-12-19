# Harbor 오프라인 설치 완벽 가이드
## nerdctl/containerd 전용 (Docker 제외)

이 문서는 완전 오프라인 RHEL 9.6 환경에서 nerdctl과 containerd를 사용하여 Harbor를 설치하는 상세한 가이드입니다.

## 📋 목차

1. [사전 요구사항](#사전-요구사항)
2. [온라인 시스템 작업](#온라인-시스템-작업)
3. [파일 전송](#파일-전송)
4. [오프라인 시스템 작업](#오프라인-시스템-작업)
5. [Harbor 설정 및 실행](#harbor-설정-및-실행)
6. [검증 및 테스트](#검증-및-테스트)
7. [문제 해결](#문제-해결)

---

## 사전 요구사항

### 온라인 시스템 (인터넷 연결)
- **OS:** RHEL 9.x 또는 호환 OS
- **필수 도구:** wget 또는 curl, tar, git
- **디스크 공간:** 최소 2GB (다운로드 및 패키징용)

### 오프라인 시스템 (RHEL 9.6)
- **OS:** RHEL 9.6
- **CPU:** 최소 2 코어 (권장 4 코어)
- **메모리:** 최소 4GB RAM (권장 8GB)
- **디스크:** 최소 40GB (권장 160GB)
- **필수 사항:**
  - **nerdctl** 및 **containerd**가 시스템 repo에서 설치 가능해야 함
  - Root 또는 sudo 권한

### 네트워크 요구사항
- 오프라인 시스템의 고정 IP 주소 또는 도메인
- 포트 80, 443 사용 가능

---

## 온라인 시스템 작업

### 1단계: 저장소 복제

```bash
# Git 저장소 복제
git clone https://github.com/pu4ro/harbor-offline-install.git
cd harbor-offline-install
```

### 2단계: 환경 설정

```bash
# 환경 설정 파일 생성
make init

# 또는 수동으로
cp env.example .env

# 설정 편집
vi .env
```

**필수 설정 항목:**
```bash
# Harbor 버전
HARBOR_VERSION=v2.11.1

# Harbor 호스트 (오프라인 시스템의 IP 또는 도메인)
HARBOR_HOSTNAME=192.168.135.96

# HTTPS 사용 여부
ENABLE_HTTPS=true

# 관리자 비밀번호
HARBOR_ADMIN_PASSWORD=Harbor12345
```

### 3단계: 필수 조건 확인

```bash
make check
```

**출력 예시:**
```
[CHECK] 시스템 요구사항 확인 중...

필수 도구 확인:
✓ wget/curl 설치됨
✓ tar 설치됨

디스크 공간 확인:
  사용 가능: 50G

[CHECK] 모든 요구사항 충족
```

### 4단계: Harbor 패키지 다운로드

```bash
make download
```

**이 단계에서 다운로드되는 항목:**
- Harbor 오프라인 설치 패키지 (harbor-offline-installer-v2.11.1.tgz)
- Docker Compose 바이너리
- 설치 스크립트 및 문서

**참고:** Docker RPM은 다운로드되지 않습니다. nerdctl과 containerd는 오프라인 시스템의 repo에서 설치됩니다.

### 5단계: HTTPS 인증서 생성 (선택사항)

HTTPS를 사용하려면:

```bash
make generate-certs
```

**대화형 입력:**
- Harbor 서버 IP 또는 도메인: 192.168.135.96
- 추가 SAN (선택): cr.makina.rocks,harbor.example.com

**생성되는 파일:**
- `harbor-certs/` 디렉토리
- `harbor-certs-<hostname>.tar.gz` 패키지

### 6단계: 단일 패키지로 압축

```bash
make package
```

**생성되는 파일:**
- `harbor-offline-rhel96-YYYYMMDD.tar.gz`
- `harbor-offline-rhel96-YYYYMMDD.tar.gz.md5`
- `harbor-offline-rhel96-YYYYMMDD.tar.gz.sha256`

### 📦 원클릭 온라인 작업

전체 과정을 한 번에:

```bash
make quick-online
```

이 명령은 다음을 순서대로 실행합니다:
1. `make check` - 요구사항 확인
2. `make download` - 패키지 다운로드
3. `make package` - 단일 패키지 생성

---

## 파일 전송

생성된 패키지를 오프라인 시스템으로 전송합니다.

### 방법 1: USB 드라이브

```bash
# USB 마운트
mount /dev/sdb1 /mnt/usb

# 파일 복사
cp harbor-offline-rhel96-*.tar.gz /mnt/usb/
cp harbor-certs-*.tar.gz /mnt/usb/  # HTTPS 사용 시

# USB 언마운트
umount /mnt/usb
```

### 방법 2: SCP (네트워크 연결 가능 시)

```bash
# 오프라인 서버로 전송
scp harbor-offline-rhel96-*.tar.gz root@192.168.135.96:/root/
scp harbor-certs-*.tar.gz root@192.168.135.96:/root/  # HTTPS 사용 시
```

### 방법 3: 로컬 파일 공유

```bash
# NFS, SMB 등을 통한 파일 공유
# 조직의 파일 공유 정책에 따라 전송
```

---

## 오프라인 시스템 작업

### 사전 준비: nerdctl 및 containerd 설치

**중요:** 이 단계는 시스템 repo가 설정되어 있어야 합니다.

```bash
# nerdctl 및 containerd 설치
dnf install -y nerdctl containerd

# containerd 시작 및 활성화
systemctl enable --now containerd

# 확인
nerdctl --version
systemctl status containerd
```

### 1단계: 패키지 압축 해제

```bash
# 전송받은 패키지가 있는 디렉토리로 이동
cd /root

# 압축 해제
tar -xzf harbor-offline-rhel96-YYYYMMDD.tar.gz
cd harbor-offline-install
```

### 2단계: Make 설치 확인 (필요 시)

```bash
# Make가 설치되어 있는지 확인
which make

# 설치되어 있지 않은 경우 (repo 필요)
dnf install -y make
```

### 3단계: 패키지 추출

```bash
make extract
```

**이 단계에서 수행되는 작업:**
- `harbor-offline-packages/` 디렉토리 생성
- 압축 파일 추출

### 4단계: 기본 설치

```bash
sudo make install
```

**이 단계에서 수행되는 작업:**
1. nerdctl 및 containerd 확인
2. Docker Compose 바이너리 설치 (`/usr/local/bin/docker-compose`)
3. Harbor 패키지 압축 해제 (`/opt/harbor`)
4. Harbor 이미지 로드 (nerdctl 사용)

**출력 예시:**
```
[INSTALL] Harbor 설치 시작...
[INFO] nerdctl 및 containerd 확인 중...
✓ nerdctl: nerdctl version 2.2.0
✓ containerd: 실행 중
[INFO] Docker Compose 설치 중...
✓ Docker Compose 설치 완료: Docker Compose version v2.24.5
[INFO] Harbor 패키지 압축 해제 중...
✓ Harbor 압축 해제 완료: /opt/harbor
[INFO] Harbor 이미지 로드 중...
✓ Harbor 이미지 로드 완료
```

### 5단계: 설치 확인

```bash
make verify
```

**예상 출력:**
```
Harbor 설치 검증 중...

✓ nerdctl: nerdctl version 2.2.0
✓ containerd: 실행 중
✓ docker-compose: Docker Compose version v2.24.5
✓ Harbor 디렉토리: /opt/harbor

검증 완료!
```

### 📦 원클릭 오프라인 설치

전체 오프라인 설치를 한 번에:

```bash
sudo make quick-offline
```

이 명령은 다음을 순서대로 실행합니다:
1. `make extract` - 패키지 추출
2. `make install` - Harbor 설치
3. `make verify` - 설치 확인

---

## Harbor 설정 및 실행

### 방법 1: 자동 설치 (권장)

```bash
# .env 파일이 있는 디렉토리에서
sudo make harbor-auto-install
```

이 명령은 모든 설정을 자동으로 수행합니다:
- Harbor 설정 파일 생성 및 구성
- 인증서 설정 (HTTPS 사용 시)
- Harbor 컨테이너 시작
- 방화벽 규칙 추가
- systemd 서비스 생성

### 방법 2: 수동 설치

#### 2-1. Harbor 설정 파일 준비

```bash
cd /opt/harbor

# 설정 템플릿 복사
cp harbor.yml.tmpl harbor.yml

# 설정 편집
vi harbor.yml
```

**필수 수정 항목:**

```yaml
# 1. 호스트명 설정
hostname: 192.168.135.96  # 또는 도메인 이름

# 2. HTTP 설정
http:
  port: 80

# 3. HTTPS 설정 (사용하는 경우)
https:
  port: 443
  certificate: /etc/harbor/ssl/192.168.135.96.crt
  private_key: /etc/harbor/ssl/192.168.135.96.key

# 4. 관리자 비밀번호
harbor_admin_password: Harbor12345

# 5. 데이터 저장 경로
data_volume: /data
```

#### 2-2. HTTPS 인증서 설치 (HTTPS 사용 시)

```bash
# 인증서 패키지 압축 해제
cd /root/harbor-offline-install
tar -xzf harbor-certs-*.tar.gz

# 인증서 설치
sudo make install-certs
```

#### 2-3. Harbor 준비 및 시작

```bash
cd /opt/harbor

# Harbor 준비 (설정 파일 생성)
./prepare

# Harbor 시작
nerdctl compose up -d
```

#### 2-4. 컨테이너 상태 확인

```bash
nerdctl compose ps
```

**예상 출력:** 9개의 컨테이너가 모두 `running` 상태여야 합니다.
```
NAME                 STATUS     PORTS
harbor-log           running    127.0.0.1:1514->10514/tcp
harbor-db            running
redis                running
registry             running
registryctl          running
harbor-core          running
harbor-portal        running
harbor-jobservice    running
nginx                running    0.0.0.0:80->8080/tcp, 0.0.0.0:443->8443/tcp
```

### 방화벽 설정

```bash
# HTTP 허용
firewall-cmd --permanent --add-service=http

# HTTPS 허용
firewall-cmd --permanent --add-service=https

# 방화벽 재로드
firewall-cmd --reload
```

---

## containerd 레지스트리 설정

Harbor를 nerdctl과 함께 사용하려면 containerd 설정이 필요합니다.

```bash
# 자동 설정 (권장)
sudo make configure-containerd
```

이 명령은 다음을 수행합니다:
- `/etc/containerd/certs.d/<harbor-host>/hosts.toml` 생성
- CA 인증서 설정 (HTTPS 사용 시)
- containerd 서비스 재시작

**수동 설정 예시 (HTTP):**

```bash
mkdir -p /etc/containerd/certs.d/192.168.135.96

cat > /etc/containerd/certs.d/192.168.135.96/hosts.toml << EOF
server = "http://192.168.135.96"

[host."http://192.168.135.96"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

systemctl restart containerd
```

---

## 검증 및 테스트

### Harbor 자동 테스트

```bash
make harbor-test
```

**테스트 항목:**
1. ✓ Harbor 설치 디렉토리 확인
2. ✓ Harbor 컨테이너 상태 (9개 실행 중)
3. ✓ 웹 UI 접근 테스트
4. ✓ API 인증 테스트
5. ✓ 프로젝트 목록 조회
6. ✓ 테스트 프로젝트 생성
7. ✓ 생성된 프로젝트 조회
8. ⊘ 레지스트리 로그인 (수동 확인)
9. ✓ 로그 파일 접근
10. ✓ 디스크 공간 확인

### 웹 UI 접근

```bash
# 브라우저에서 접속
http://192.168.135.96   # HTTP
https://192.168.135.96  # HTTPS
```

**로그인 정보:**
- 사용자명: `admin`
- 비밀번호: `.env`에서 설정한 비밀번호

### nerdctl 로그인 테스트

```bash
# Harbor 로그인
nerdctl login 192.168.135.96

# 사용자명: admin
# 비밀번호: Harbor12345 (또는 설정한 비밀번호)
```

### 이미지 Push/Pull 테스트

```bash
# 1. 테스트 이미지 pull
nerdctl pull nginx:latest

# 2. Harbor로 tag
nerdctl tag nginx:latest 192.168.135.96/library/nginx:test

# 3. Harbor로 push
nerdctl push 192.168.135.96/library/nginx:test

# 4. 이미지 삭제 후 pull 테스트
nerdctl rmi 192.168.135.96/library/nginx:test
nerdctl pull 192.168.135.96/library/nginx:test
```

---

## Harbor 서비스 관리

### Make 명령어 사용

```bash
# Harbor 시작
make harbor-start

# Harbor 중지
make harbor-stop

# Harbor 재시작
make harbor-restart

# Harbor 상태 확인
make harbor-status

# Harbor 로그 확인
make harbor-logs
```

### 수동 관리

```bash
cd /opt/harbor

# 시작
nerdctl compose up -d

# 중지
nerdctl compose down

# 재시작
nerdctl compose restart

# 상태 확인
nerdctl compose ps

# 로그 확인
nerdctl compose logs -f
```

---

## 문제 해결

### 1. nerdctl이 설치되어 있지 않음

**증상:**
```
nerdctl이 설치되어 있지 않습니다.
설치 방법: dnf install -y nerdctl
```

**해결:**
```bash
# 시스템 repo가 설정되어 있는지 확인
dnf repolist

# nerdctl 설치
dnf install -y nerdctl containerd

# 서비스 시작
systemctl enable --now containerd
```

### 2. Harbor 컨테이너가 시작되지 않음

**증상:**
```
nerdctl compose ps  # 일부 컨테이너만 running
```

**해결:**
```bash
# 로그 확인
cd /opt/harbor
nerdctl compose logs

# 특정 컨테이너 로그 확인
nerdctl compose logs harbor-core

# 재시작
nerdctl compose restart
```

### 3. 웹 UI 502 Bad Gateway

**증상:**
브라우저에서 502 에러 발생

**해결:**
```bash
# Harbor 재시작
cd /opt/harbor
nerdctl compose restart

# 10초 대기 후 재접속
sleep 10
```

### 4. nerdctl 로그인 실패

**증상:**
```
unexpected status code 502
```

**해결:**
```bash
# containerd 설정 확인
sudo make configure-containerd

# containerd 재시작
systemctl restart containerd

# 10초 대기 후 재시도
sleep 10
nerdctl login 192.168.135.96
```

### 5. 디스크 공간 부족

**확인:**
```bash
df -h /data
```

**해결:**
```bash
# Harbor 정리
cd /opt/harbor
nerdctl compose exec registry registry garbage-collect /etc/registry/config.yml

# 또는 Docker 정리
nerdctl system prune -a
```

---

## 추가 리소스

### 문서
- `README-KR.md` - 전체 설치 가이드
- `QUICKSTART.md` - 빠른 시작 가이드
- `CLAUDE.md` - 개발자 가이드
- `README-K8S.md` - Kubernetes 통합 가이드

### 명령어 참조

```bash
# 도움말
make help

# 시스템 정보
make info

# 문서 목록
make docs

# 전체 테스트
make test-all
```

---

## 요약: 완전 오프라인 설치 순서

### 온라인 시스템
```bash
git clone https://github.com/pu4ro/harbor-offline-install.git
cd harbor-offline-install
make init
vi .env  # 설정 편집
make quick-online  # 다운로드 + 패키징
make generate-certs  # HTTPS 사용 시
# 파일을 오프라인 시스템으로 전송
```

### 오프라인 시스템
```bash
# 1. nerdctl/containerd 설치 (repo 필요)
dnf install -y nerdctl containerd
systemctl enable --now containerd

# 2. 패키지 압축 해제 및 설치
cd /root
tar -xzf harbor-offline-rhel96-*.tar.gz
cd harbor-offline-install
sudo make quick-offline  # 압축 해제 + 설치 + 검증

# 3. Harbor 자동 설치 (권장)
sudo make harbor-auto-install

# 4. containerd 설정
sudo make configure-containerd

# 5. 테스트
make harbor-test

# 6. 웹 UI 접속
# https://192.168.135.96
# admin / Harbor12345
```

설치 완료! 🎉

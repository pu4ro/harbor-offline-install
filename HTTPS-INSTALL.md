# Harbor HTTPS 설치 가이드

Harbor를 HTTPS로 설치하는 간단한 가이드입니다.

---

## 빠른 시작

```bash
# 1. 환경 설정
cd harbor-offline-install
cp env.example .env
vi .env  # HARBOR_HOSTNAME, ENABLE_HTTPS 설정

# 2. 인증서 생성
./generate-certs.sh

# 3. Harbor 설치
make harbor-auto-install

# 4. containerd 설정
./configure-containerd.sh

# 5. 테스트
nerdctl login ${HARBOR_HOSTNAME}
```

---

## 1. 환경 설정 (.env)

### 필수 설정 항목

```bash
# Harbor 호스트명 (IP 또는 도메인)
HARBOR_HOSTNAME=192.168.135.96

# HTTPS 활성화
ENABLE_HTTPS=true

# 포트 설정
HARBOR_HTTPS_PORT=443
HARBOR_HTTP_PORT=80

# 관리자 비밀번호
HARBOR_ADMIN_PASSWORD=Harbor12345

# 추가 도메인 (선택)
CERT_ADDITIONAL_SANS=cr.makina.rocks

# 시스템 설정
DISABLE_SELINUX=true
AUTO_CONFIGURE_FIREWALL=true
CREATE_SYSTEMD_SERVICE=true
```

---

## 2. SSL 인증서 생성

### 자동 생성 (권장)

```bash
./generate-certs.sh
```

`.env` 파일의 `HARBOR_HOSTNAME`을 자동으로 읽어 인증서 생성

### 생성 결과 확인

```bash
ls -la harbor-certs/
# ca.crt, ca.key
# ${HARBOR_HOSTNAME}.crt, ${HARBOR_HOSTNAME}.key
```

---

## 3. Harbor 설치

### Make 명령어

```bash
# 전체 자동 설치
make harbor-auto-install
```

### 설치 단계 (자동 수행)

1. **Step 0/7:** SELinux/firewalld 설정
2. **Step 1/7:** nerdctl/containerd 확인
3. **Step 2/7:** nerdctl compose 확인
4. **Step 3/7:** 인증서 검증 및 패키지 압축 해제
5. **Step 4/7:** harbor.yml HTTPS 설정
6. **Step 5/7:** 데이터 디렉토리 생성
7. **Step 6/7:** Harbor 컨테이너 시작
8. **Step 7/7:** 방화벽 및 systemd 서비스 등록

### 설치 확인

```bash
cd /opt/harbor
nerdctl compose ps
# 9개 컨테이너 모두 'running' 상태 확인
```

---

## 4. containerd 설정

### 자동 설정

```bash
./configure-containerd.sh
```

자동으로 수행:
- CA 인증서 복사
- `/etc/containerd/certs.d/${HARBOR_HOSTNAME}/hosts.toml` 생성
- containerd 재시작

### CA 인증서 시스템 등록

```bash
cp harbor-certs/ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt
update-ca-trust
```

### 추가 도메인 설정 (선택)

cr.makina.rocks 같은 추가 도메인:

```bash
mkdir -p /etc/containerd/certs.d/cr.makina.rocks

cat > /etc/containerd/certs.d/cr.makina.rocks/hosts.toml <<EOF
server = "https://cr.makina.rocks:443"

[host."https://cr.makina.rocks:443"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/pki/ca-trust/source/anchors/harbor-ca.crt"
  skip_verify = false
EOF

systemctl restart containerd
```

---

## 5. 테스트

### HTTPS 접속

```bash
curl -I https://${HARBOR_HOSTNAME}
# HTTP/1.1 200 OK
```

### 로그인

```bash
echo "${HARBOR_ADMIN_PASSWORD}" | nerdctl login ${HARBOR_HOSTNAME} -u admin --password-stdin
# Login Succeeded
```

### 프로젝트 생성

```bash
curl -X POST "https://${HARBOR_HOSTNAME}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:${HARBOR_ADMIN_PASSWORD}" \
  -d '{"project_name":"test-project", "public":false}'
```

### 이미지 Push/Pull

```bash
# 이미지 다운로드
nerdctl pull alpine:latest

# Harbor에 태그
nerdctl tag alpine:latest ${HARBOR_HOSTNAME}/test-project/alpine:latest

# Push
nerdctl push ${HARBOR_HOSTNAME}/test-project/alpine:latest

# Pull
nerdctl pull ${HARBOR_HOSTNAME}/test-project/alpine:latest
```

---

## 주요 Make 명령어

### 설치

```bash
make download             # Harbor 패키지 다운로드
make harbor-auto-install  # 자동 설치
```

### 관리

```bash
make harbor-status        # 상태 확인
make harbor-start         # 시작
make harbor-stop          # 중지
make harbor-restart       # 재시작
make harbor-logs          # 로그 확인
```

### 제거

```bash
make harbor-uninstall     # 완전 제거
```

### systemd

```bash
make harbor-enable-service   # 서비스 활성화
systemctl status harbor      # 상태 확인
```

---

## 문제 해결

### 1. nerdctl login 실패

```bash
# containerd hosts.toml에 포트 명시
cat > /etc/containerd/certs.d/${HARBOR_HOSTNAME}/hosts.toml <<EOF
server = "https://${HARBOR_HOSTNAME}:443"

[host."https://${HARBOR_HOSTNAME}:443"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/${HARBOR_HOSTNAME}/ca.crt"
  skip_verify = false
EOF

systemctl restart containerd
```

### 2. 502 Bad Gateway

```bash
cd /opt/harbor
nerdctl compose restart
# 또는
nerdctl compose down && nerdctl compose up -d
```

### 3. SELinux 오류

```bash
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
```

### 4. 방화벽 차단

```bash
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload
```

### 5. 완전 재설치

```bash
make harbor-uninstall
make harbor-auto-install
```

---

## Web UI 접속

- **URL:** https://${HARBOR_HOSTNAME}
- **사용자:** admin
- **비밀번호:** .env의 HARBOR_ADMIN_PASSWORD

---

## 설치 체크리스트

- [ ] `.env` 파일 설정 (ENABLE_HTTPS=true)
- [ ] 인증서 생성 완료
- [ ] Harbor 9개 컨테이너 running
- [ ] HTTPS 접속 성공 (200 OK)
- [ ] nerdctl login 성공
- [ ] 이미지 push/pull 동작
- [ ] systemd 서비스 활성화
- [ ] 방화벽 포트 오픈 (80, 443)

# Harbor 오프라인 설치 빠른 시작 가이드

이 가이드는 Harbor를 빠르게 설치하는 방법을 제공합니다.

## 목차
- [Docker 환경](#docker-환경)
- [nerdctl/containerd 환경](#nerdctlcontainerd-환경)
- [사설 인증서로 HTTPS 사용](#사설-인증서로-https-사용)

---

## 사전 준비

### 1. .env 파일 생성

```bash
cp env.example .env
vi .env
```

**필수 수정 항목**:
```bash
HARBOR_HOSTNAME=192.168.1.100  # 실제 서버 IP로 변경
HARBOR_ADMIN_PASSWORD=YourSecurePassword123!  # 보안 비밀번호로 변경
```

---

## Docker 환경

### 온라인 시스템 (인터넷 연결됨)

```bash
# 1. 패키지 다운로드
make download

# 2. 패키지 압축
make package
```

생성된 `harbor-offline-rhel96-YYYYMMDD.tar.gz` 파일을 오프라인 시스템으로 전송

### 오프라인 시스템 (RHEL 9.6)

```bash
# 1. 압축 해제
tar -xzf harbor-offline-rhel96-YYYYMMDD.tar.gz
cd harbor-offline-packages

# 2. 설치
sudo ./install-offline.sh

# 3. Harbor 설정
cd /opt/harbor
sudo cp harbor.yml.tmpl harbor.yml
sudo vi harbor.yml  # hostname과 비밀번호 수정

# 4. Harbor 시작
sudo ./install.sh

# 5. 확인
docker-compose ps
```

---

## nerdctl/containerd 환경

K8s 설치 전 이미지 registry로 사용하는 경우

### 1. 환경 변수 설정

```bash
vi .env
```

```bash
SKIP_DOCKER_INSTALL=true
CONTAINER_RUNTIME=nerdctl
```

### 2. Harbor 설치 (온라인 시스템에서 패키지 준비 후)

```bash
cd harbor-offline-packages
sudo chmod +x install-harbor-nerdctl.sh
sudo ./install-harbor-nerdctl.sh
```

### 3. nerdctl insecure registry 설정 (HTTP 사용 시)

```bash
# /etc/nerdctl/nerdctl.toml 생성
sudo mkdir -p /etc/nerdctl
sudo tee /etc/nerdctl/nerdctl.toml > /dev/null <<EOF
[registry."192.168.1.100"]
  insecure = true
EOF
```

또는 containerd 설정:

```bash
sudo vi /etc/containerd/config.toml
```

추가:
```toml
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.100".tls]
  insecure_skip_verify = true
```

```bash
sudo systemctl restart containerd
```

### 4. Harbor 사용

```bash
# 로그인
nerdctl login 192.168.1.100

# 이미지 태그
nerdctl tag myimage:latest 192.168.1.100/library/myimage:latest

# 이미지 Push
nerdctl push 192.168.1.100/library/myimage:latest
```

---

## 사설 인증서로 HTTPS 사용

### 1. 인증서 생성 (온라인 시스템)

```bash
# .env 파일에서 HTTPS 설정
vi .env
```

```bash
ENABLE_HTTPS=true
HARBOR_HOSTNAME=192.168.1.100
```

```bash
# 인증서 생성
make generate-certs
```

### 2. 인증서 패키지 전송

생성된 `harbor-certs-*.tar.gz` 파일을 오프라인 시스템으로 전송

### 3. 인증서 설치 (오프라인 시스템)

```bash
# 인증서 압축 해제
tar -xzf harbor-certs-192.168.1.100.tar.gz
cd harbor-certs

# 인증서 설치
sudo ./install-certs.sh
```

### 4. Harbor 설정에서 HTTPS 활성화

```bash
cd /opt/harbor
sudo vi harbor.yml
```

HTTPS 섹션 활성화:
```yaml
hostname: 192.168.1.100

https:
  port: 443
  certificate: /etc/harbor/ssl/192.168.1.100.crt
  private_key: /etc/harbor/ssl/192.168.1.100.key
```

### 5. Harbor 재설치

```bash
cd /opt/harbor
sudo ./install.sh
```

### 6. 클라이언트에서 CA 인증서 설치

**RHEL/CentOS**:
```bash
sudo cp ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt
sudo update-ca-trust
```

**Ubuntu/Debian**:
```bash
sudo cp ca.crt /usr/local/share/ca-certificates/harbor-ca.crt
sudo update-ca-certificates
```

**nerdctl 사용 시**:
```bash
# CA 인증서를 시스템에 추가한 후 containerd 재시작
sudo systemctl restart containerd
```

---

## Makefile 명령어 요약

```bash
make help              # 모든 명령어 확인
make download          # 패키지 다운로드
make generate-certs    # HTTPS 인증서 생성
make package           # 패키지 압축
make extract           # 패키지 압축 해제
make install           # Harbor 설치
make verify            # 설치 확인
make harbor-start      # Harbor 시작
make harbor-stop       # Harbor 중지
make harbor-status     # Harbor 상태 확인
```

---

## 자주 사용하는 명령어

### Harbor 관리

```bash
# 상태 확인
cd /opt/harbor
docker-compose ps  # 또는 nerdctl compose ps

# 로그 확인
docker-compose logs -f

# 재시작
docker-compose restart

# 중지
docker-compose down

# 시작
docker-compose up -d
```

### Docker/nerdctl 사용

```bash
# 로그인
docker login 192.168.1.100  # 또는 nerdctl login

# 이미지 태그
docker tag myimage:latest 192.168.1.100/library/myimage:latest

# 이미지 Push
docker push 192.168.1.100/library/myimage:latest

# 이미지 Pull
docker pull 192.168.1.100/library/myimage:latest
```

---

## K8s에서 Harbor 사용

### imagePullSecret 생성

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=192.168.1.100 \
  --docker-username=admin \
  --docker-password=<your-password> \
  --namespace=default
```

### Pod에서 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: my-container
    image: 192.168.1.100/library/myimage:latest
  imagePullSecrets:
  - name: harbor-registry
```

---

## 문제 해결

### 1. Harbor에 접속할 수 없는 경우

```bash
# 방화벽 확인
sudo firewall-cmd --list-all

# 포트 열기
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

### 2. SELinux 문제

```bash
# 임시 비활성화
sudo setenforce 0

# 영구 비활성화 (재부팅 필요)
sudo vi /etc/selinux/config
# SELINUX=permissive로 변경
```

### 3. insecure registry 오류

**Docker**:
```bash
sudo vi /etc/docker/daemon.json
```
```json
{
  "insecure-registries": ["192.168.1.100"]
}
```
```bash
sudo systemctl restart docker
```

**nerdctl**:
```bash
sudo vi /etc/nerdctl/nerdctl.toml
```
```toml
[registry."192.168.1.100"]
  insecure = true
```

---

## 추가 정보

- 상세 설치 가이드: [README-KR.md](README-KR.md)
- 환경 변수 설정: [env.example](env.example)
- Harbor 공식 문서: https://goharbor.io/docs/

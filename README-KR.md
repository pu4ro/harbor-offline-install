# Harbor 오프라인 설치 가이드 (RHEL 9.6)

이 가이드는 인터넷이 연결되지 않은 RHEL 9.6 환경에서 Harbor를 설치하는 방법을 제공합니다.

## 주요 기능

- **Makefile 기반 관리**: 모든 스크립트를 `make` 명령으로 간편하게 실행
- **환경 변수 관리**: `.env` 파일을 통한 중앙 집중식 설정 관리
- **HTTPS 지원**: 사설 인증서 자동 생성 및 설치
- **다양한 런타임 지원**:
  - Docker/Docker Compose
  - nerdctl/containerd (K8s 설치 전 registry 용도)
- **완전 자동화**: 다운로드부터 설치까지 원클릭 실행

## 빠른 시작

**처음 사용하시나요?** [빠른 시작 가이드](QUICK-START-KR.md)를 먼저 확인하세요!

**Makefile 사용법 확인**:
```bash
make help
```

## 목차
- [사전 요구사항](#사전-요구사항)
- [환경 설정 (.env)](#환경-설정-env)
- [Makefile 사용법](#makefile-사용법)
- [Docker 환경 설치](#docker-환경-설치)
- [nerdctl/containerd 환경 설치](#nerdctlcontainerd-환경-설치)
- [HTTPS 설정](#https-설정)
- [1단계: 온라인 시스템에서 파일 다운로드](#1단계-온라인-시스템에서-파일-다운로드)
- [2단계: 오프라인 시스템으로 파일 전송](#2단계-오프라인-시스템으로-파일-전송)
- [3단계: 오프라인 설치 실행](#3단계-오프라인-설치-실행)
- [4단계: Harbor 설정 및 시작](#4단계-harbor-설정-및-시작)
- [K8s에서 Harbor 사용](#k8s에서-harbor-사용)
- [문제 해결](#문제-해결)

## 환경 설정 (.env)

모든 설정은 `.env` 파일에서 관리됩니다.

```bash
# .env 파일 생성
cp env.example .env

# 설정 편집
vi .env
```

**주요 설정 항목**:
```bash
# Harbor 기본 설정
HARBOR_VERSION=v2.11.1
HARBOR_HOSTNAME=192.168.1.100
HARBOR_ADMIN_PASSWORD=Harbor12345  # 반드시 변경!

# HTTPS 사용
ENABLE_HTTPS=false  # true로 변경하면 HTTPS 활성화

# 컨테이너 런타임 (docker/nerdctl/auto)
CONTAINER_RUNTIME=auto
SKIP_DOCKER_INSTALL=false  # nerdctl 사용 시 true

# Kubernetes 설정 (K8s 설치 전 registry 용도로 사용)
USE_KUBERNETES=false
```

전체 설정 옵션은 [env.example](env.example) 파일을 참조하세요.

## Makefile 사용법

모든 작업은 `make` 명령으로 수행할 수 있습니다.

### 도움말 보기
```bash
make help
```

### 주요 명령어

**온라인 시스템 (패키지 다운로드)**:
```bash
make download          # Harbor 및 의존성 다운로드
make generate-certs    # HTTPS용 인증서 생성 (선택)
make package           # 단일 tar.gz 파일로 압축
```

**오프라인 시스템 (설치)**:
```bash
make extract           # 패키지 압축 해제
make install           # Harbor 설치 (root 권한 필요)
make install-certs     # HTTPS 인증서 설치 (선택)
make verify            # 설치 확인
```

**Harbor 관리**:
```bash
make harbor-start      # Harbor 시작
make harbor-stop       # Harbor 중지
make harbor-status     # 상태 확인
make harbor-logs       # 로그 확인
make harbor-restart    # 재시작
```

**원클릭 실행**:
```bash
make quick-online      # 온라인 시스템에서 다운로드+패키징
make quick-offline     # 오프라인 시스템에서 설치+검증
```

## Docker 환경 설치

### 온라인 시스템
```bash
make quick-online
```

### 오프라인 시스템
```bash
# 전송받은 패키지 압축 해제
tar -xzf harbor-offline-rhel96-YYYYMMDD.tar.gz

# 설치
sudo make quick-offline
```

## nerdctl/containerd 환경 설치

K8s 설치 전에 이미지 registry로 Harbor를 사용하는 경우

### 1. 환경 변수 설정
```bash
vi .env
```
```bash
SKIP_DOCKER_INSTALL=true
CONTAINER_RUNTIME=nerdctl
```

### 2. 설치
```bash
cd harbor-offline-packages
sudo chmod +x install-harbor-nerdctl.sh
sudo ./install-harbor-nerdctl.sh
```

### 3. nerdctl에서 insecure registry 설정 (HTTP 사용 시)
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
```toml
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.100".tls]
  insecure_skip_verify = true
```
```bash
sudo systemctl restart containerd
```

## HTTPS 설정

### 1. 사설 인증서 생성 (온라인 시스템)
```bash
# .env에서 HTTPS 활성화
vi .env
```
```bash
ENABLE_HTTPS=true
HARBOR_HOSTNAME=192.168.1.100  # 실제 IP로 변경
```
```bash
# 인증서 생성
make generate-certs
```

### 2. 인증서 설치 (오프라인 시스템)
```bash
# 인증서 패키지 압축 해제
tar -xzf harbor-certs-192.168.1.100.tar.gz

# 인증서 설치
sudo make install-certs
```

### 3. Harbor 설정에서 HTTPS 활성화
```bash
cd /opt/harbor
sudo vi harbor.yml
```
HTTPS 섹션 활성화 및 인증서 경로 설정

자세한 내용은 [빠른 시작 가이드](QUICK-START-KR.md#사설-인증서로-https-사용)를 참조하세요.

## 사전 요구사항

### 하드웨어 요구사항
- **CPU**: 최소 2 코어 (권장 4 코어)
- **메모리**: 최소 4GB RAM (권장 8GB)
- **디스크**: 최소 40GB 여유 공간 (권장 160GB)

### 네트워크 요구사항
- 오프라인 시스템의 고정 IP 주소
- 포트 80, 443이 사용 가능해야 함

## 1단계: 온라인 시스템에서 파일 다운로드

인터넷이 연결된 시스템(Linux)에서 다음 스크립트를 실행합니다:

```bash
# 다운로드 스크립트에 실행 권한 부여
chmod +x download-packages.sh

# 스크립트 실행
./download-packages.sh
```

이 스크립트는 다음을 다운로드합니다:
- Harbor 오프라인 설치 패키지 (최신 버전)
- Docker Engine RPM 패키지
- Docker Compose
- 필요한 모든 의존성 패키지

다운로드가 완료되면 `harbor-offline-packages` 디렉토리가 생성됩니다.

## 2단계: 오프라인 시스템으로 파일 전송

다운로드한 `harbor-offline-packages` 디렉토리를 오프라인 RHEL 9.6 시스템으로 전송합니다:

```bash
# USB 또는 네트워크를 통해 전송
# 예: scp를 사용하는 경우
scp -r harbor-offline-packages user@offline-server:/root/
```

또는 USB 드라이브를 사용:
1. `harbor-offline-packages` 디렉토리를 USB에 복사
2. USB를 오프라인 시스템에 연결
3. 파일을 적절한 위치로 복사

## 3단계: 오프라인 설치 실행

오프라인 RHEL 9.6 시스템에서:

```bash
# 설치 디렉토리로 이동
cd harbor-offline-packages

# 설치 스크립트에 실행 권한 부여
chmod +x install-offline.sh

# 설치 실행 (root 권한 필요)
sudo ./install-offline.sh
```

설치 스크립트는 다음을 수행합니다:
1. Docker 및 의존성 패키지 설치
2. Docker Compose 설치
3. Docker 서비스 시작 및 활성화
4. Harbor 설치 파일 압축 해제

## 4단계: Harbor 설정 및 시작

### 4.1 Harbor 설정

```bash
# Harbor 디렉토리로 이동
cd /opt/harbor

# 설정 파일 복사
cp harbor.yml.tmpl harbor.yml

# 설정 파일 편집
vi harbor.yml
```

**필수 수정 사항**:

```yaml
# 호스트명을 시스템의 IP 또는 FQDN으로 변경
hostname: your-server-ip-or-fqdn

# HTTP 설정
http:
  port: 80

# HTTPS 설정 (선택사항, 인증서가 있는 경우)
# https:
#   port: 443
#   certificate: /your/certificate/path
#   private_key: /your/private/key/path

# 초기 관리자 비밀번호 (반드시 변경하세요!)
harbor_admin_password: Harbor12345

# 데이터 저장 경로
data_volume: /data
```

### 4.2 Harbor 설치 스크립트 실행

```bash
# Harbor 설치 실행
sudo ./install.sh

# Notary와 Trivy를 포함하여 설치하려면:
# sudo ./install.sh --with-notary --with-trivy
```

### 4.3 설치 확인

```bash
# Docker 컨테이너 확인
docker-compose ps

# 모든 서비스가 "Up" 상태여야 합니다
```

웹 브라우저에서 접속:
- URL: `http://your-server-ip` 또는 `https://your-server-ip`
- 기본 계정: `admin`
- 비밀번호: harbor.yml에서 설정한 비밀번호

## Harbor 서비스 관리

### 시작/중지/재시작

```bash
cd /opt/harbor

# Harbor 중지
sudo docker-compose down

# Harbor 시작
sudo docker-compose up -d

# Harbor 재시작
sudo docker-compose restart

# 로그 확인
sudo docker-compose logs -f
```

### 시스템 부팅 시 자동 시작

```bash
# systemd 서비스 파일 생성
sudo tee /etc/systemd/system/harbor.service > /dev/null <<'EOF'
[Unit]
Description=Harbor
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/harbor
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
User=root

[Install]
WantedBy=multi-user.target
EOF

# 서비스 활성화
sudo systemctl daemon-reload
sudo systemctl enable harbor
sudo systemctl start harbor
```

## 방화벽 설정

```bash
# 방화벽이 활성화된 경우
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## Docker 클라이언트에서 Harbor 사용

### HTTP를 사용하는 경우 (비보안)

각 Docker 클라이언트에서:

```bash
# /etc/docker/daemon.json 편집
sudo vi /etc/docker/daemon.json
```

다음 내용 추가:

```json
{
  "insecure-registries": ["your-harbor-ip"]
}
```

```bash
# Docker 재시작
sudo systemctl restart docker
```

### Harbor 로그인

```bash
# Harbor에 로그인
docker login your-harbor-ip

# 사용자명: admin
# 비밀번호: harbor.yml에서 설정한 비밀번호
```

### 이미지 Push/Pull

```bash
# 이미지 태그
docker tag my-image:latest your-harbor-ip/library/my-image:latest

# 이미지 Push
docker push your-harbor-ip/library/my-image:latest

# 이미지 Pull
docker pull your-harbor-ip/library/my-image:latest
```

## 문제 해결

### 1. Docker 서비스가 시작되지 않는 경우

```bash
# Docker 상태 확인
sudo systemctl status docker

# 로그 확인
sudo journalctl -u docker -n 50
```

### 2. Harbor 컨테이너가 시작되지 않는 경우

```bash
# Docker Compose 로그 확인
cd /opt/harbor
sudo docker-compose logs

# 특정 서비스 로그 확인
sudo docker-compose logs harbor-core
```

### 3. 웹 UI에 접속할 수 없는 경우

- 방화벽 설정 확인
- SELinux 상태 확인: `sudo getenforce`
- 포트가 사용 중인지 확인: `sudo netstat -tulpn | grep -E ':(80|443)'`

### 4. 디스크 공간 부족

```bash
# Docker 정리
sudo docker system prune -a

# Harbor 로그 정리
cd /opt/harbor
sudo docker-compose exec registry registry garbage-collect /etc/registry/config.yml
```

### 5. SELinux 문제

```bash
# SELinux를 permissive 모드로 변경 (임시)
sudo setenforce 0

# 영구적으로 변경하려면 /etc/selinux/config 편집
sudo vi /etc/selinux/config
# SELINUX=permissive로 변경
```

## 백업 및 복원

### 백업

```bash
# Harbor 중지
cd /opt/harbor
sudo docker-compose down

# 데이터 백업
sudo tar -czf harbor-backup-$(date +%Y%m%d).tar.gz /data

# Harbor 시작
sudo docker-compose up -d
```

### 복원

```bash
# Harbor 중지
cd /opt/harbor
sudo docker-compose down

# 기존 데이터 삭제 (주의!)
sudo rm -rf /data/*

# 백업 복원
sudo tar -xzf harbor-backup-YYYYMMDD.tar.gz -C /

# Harbor 시작
sudo docker-compose up -d
```

## 업그레이드

새 버전의 Harbor로 업그레이드하려면:

1. 현재 Harbor 백업
2. 새 버전의 오프라인 패키지 다운로드
3. Harbor 공식 문서의 마이그레이션 가이드 참조

## 추가 리소스

- Harbor 공식 문서: https://goharbor.io/docs/
- GitHub 리포지토리: https://github.com/goharbor/harbor

## 버전 정보

- 지원 OS: RHEL 9.6
- Harbor 버전: 2.11.x (다운로드 스크립트에서 최신 버전 확인)
- Docker 버전: 최신 안정 버전
- Docker Compose 버전: v2.x

## 라이선스

Harbor는 Apache License 2.0에 따라 배포됩니다.

## K8s에서 Harbor 사용

K8s 클러스터에서 Harbor를 private registry로 사용하는 방법입니다.

### 1. imagePullSecret 생성

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=192.168.1.100 \
  --docker-username=admin \
  --docker-password=<Harbor-Admin-Password> \
  --namespace=default
```

다른 네임스페이스에서 사용하려면:
```bash
# 모든 네임스페이스에 secret 생성
for ns in default kube-system kube-public; do
  kubectl create secret docker-registry harbor-registry \
    --docker-server=192.168.1.100 \
    --docker-username=admin \
    --docker-password=<password> \
    --namespace=$ns
done
```

### 2. Pod에서 Harbor 이미지 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app-container
    image: 192.168.1.100/library/my-app:latest
  imagePullSecrets:
  - name: harbor-registry
```

### 3. Deployment 예제

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: 192.168.1.100/library/my-app:v1.0
        ports:
        - containerPort: 8080
      imagePullSecrets:
      - name: harbor-registry
```

### 4. ServiceAccount에 imagePullSecret 설정

전역으로 사용하려면:

```bash
# default ServiceAccount에 추가
kubectl patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "harbor-registry"}]}' \
  -n default
```

이제 해당 네임스페이스의 모든 Pod가 자동으로 Harbor를 사용할 수 있습니다.

### 5. 클라이언트 시스템에 CA 인증서 추가

HTTPS를 사용하는 경우, K8s 노드에 Harbor CA 인증서를 추가:

```bash
# 각 K8s 노드에서 실행
sudo ./add-harbor-ca.sh ca.crt 192.168.1.100
```

또는 Makefile 사용:
```bash
sudo make add-ca
```

## 클라이언트 시스템 설정

Harbor를 사용할 모든 시스템에서 CA 인증서를 추가해야 합니다.

### CA 인증서 배포

**Harbor 서버에서 CA 인증서 복사**:
```bash
# Harbor 서버에서
scp harbor-certs/ca.crt user@client-system:/tmp/
```

**클라이언트 시스템에서 CA 추가**:
```bash
# add-harbor-ca.sh 스크립트 사용 (권장)
sudo ./add-harbor-ca.sh /tmp/ca.crt 192.168.1.100
```

또는 수동 설치:

**RHEL/CentOS**:
```bash
sudo cp /tmp/ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt
sudo update-ca-trust
```

**Ubuntu/Debian**:
```bash
sudo cp /tmp/ca.crt /usr/local/share/ca-certificates/harbor-ca.crt
sudo update-ca-certificates
```

**nerdctl/containerd 사용 시**:
```bash
# CA 인증서를 시스템에 추가한 후
sudo systemctl restart containerd
```

### 연결 테스트

```bash
# Harbor 로그인 테스트
docker login 192.168.1.100
# 또는
nerdctl login 192.168.1.100

# 이미지 Push/Pull 테스트
docker pull nginx:latest
docker tag nginx:latest 192.168.1.100/library/nginx:latest
docker push 192.168.1.100/library/nginx:latest
```

## 자동화된 CA 배포

여러 클라이언트 시스템에 CA를 배포하려면:

```bash
# hosts.txt 파일 생성 (한 줄에 하나씩 호스트 입력)
cat > hosts.txt <<EOF
node1.example.com
node2.example.com
node3.example.com

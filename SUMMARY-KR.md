# Harbor 오프라인 설치 프로젝트 요약

## 프로젝트 개요

RHEL 9.6 환경에서 Harbor를 오프라인으로 설치하기 위한 완전 자동화 도구 모음입니다.

## 주요 기능

### 1. Makefile 기반 관리
- 모든 스크립트를 `make` 명령으로 간편하게 실행
- `make help` 명령으로 모든 사용 가능한 명령 확인
- 원클릭 실행 지원 (`make quick-online`, `make quick-offline`)

### 2. 환경 변수 중앙 관리
- `.env` 파일을 통한 모든 설정 관리
- `env.example`에 상세한 설명과 예제 제공
- 버전, 호스트명, 비밀번호, 포트 등 모든 설정 가능

### 3. 사설 인증서 자동 생성
- OpenSSL을 사용한 자체 서명 인증서 생성
- CA, 서버 인증서, Docker/nerdctl용 포맷 자동 변환
- SAN (Subject Alternative Name) 지원

### 4. 다양한 컨테이너 런타임 지원
- **Docker/Docker Compose**: 기본 설치 방식
- **nerdctl/containerd**: K8s 설치 전 registry 용도
- 자동 감지 기능으로 환경에 맞게 설치

### 5. insecure registry 문제 해결
- `add-harbor-ca.sh` 스크립트로 CA 인증서 시스템에 자동 등록
- Docker, containerd, nerdctl, Podman 모두 지원
- 클라이언트 시스템에도 쉽게 배포 가능

### 6. Kubernetes 통합
- imagePullSecret 생성 가이드
- K8s 노드 설정 방법
- containerd/crictl 사용법
- 별도의 K8s 통합 가이드 문서 (README-K8S.md)

## 파일 구조

```
harbor-offline-install/
├── Makefile                      # 모든 작업을 관리하는 메인 Makefile
├── .env                          # 환경 변수 설정 파일
├── env.example                   # 환경 변수 예제 및 설명
├── .gitignore                    # Git 제외 파일 목록
│
├── README-KR.md                  # 상세 설치 가이드 (한국어)
├── QUICK-START-KR.md             # 빠른 시작 가이드
├── README-K8S.md                 # Kubernetes 통합 가이드
├── SUMMARY-KR.md                 # 이 파일 (프로젝트 요약)
│
├── download-packages.sh          # 온라인 시스템에서 패키지 다운로드
├── create-package.sh             # 다운로드한 파일을 tar.gz로 압축
├── generate-certs.sh             # HTTPS용 자체 서명 인증서 생성
├── add-harbor-ca.sh              # CA 인증서를 시스템에 등록
│
├── install-harbor-nerdctl.sh     # nerdctl 환경용 Harbor 설치
└── harbor-config-example.yml     # Harbor 설정 예제
```

## 설치 워크플로우

### 온라인 시스템 (인터넷 연결됨)

```bash
# 1. 환경 설정
cp env.example .env
vi .env  # HARBOR_HOSTNAME, 비밀번호 등 수정

# 2. 패키지 다운로드
make download

# 3. (선택) HTTPS용 인증서 생성
make generate-certs

# 4. 단일 패키지로 압축
make package

# 생성된 파일:
# - harbor-offline-rhel96-YYYYMMDD.tar.gz
# - harbor-certs-192.168.1.100.tar.gz (HTTPS 사용 시)
```

### 오프라인 시스템 (RHEL 9.6)

#### Docker 환경

```bash
# 1. 패키지 압축 해제
tar -xzf harbor-offline-rhel96-YYYYMMDD.tar.gz

# 2. 설치
sudo make quick-offline

# 3. Harbor 설정
cd /opt/harbor
sudo vi harbor.yml  # hostname, 비밀번호 수정

# 4. Harbor 시작
sudo ./install.sh
```

#### nerdctl/containerd 환경 (K8s 설치 전 registry 용도)

```bash
# 1. 환경 변수 설정
vi .env
# SKIP_DOCKER_INSTALL=true
# CONTAINER_RUNTIME=nerdctl

# 2. nerdctl 전용 설치
cd harbor-offline-packages
sudo ./install-harbor-nerdctl.sh

# 3. insecure registry 설정 (HTTP 사용 시)
sudo mkdir -p /etc/nerdctl
sudo tee /etc/nerdctl/nerdctl.toml > /dev/null <<EOF
[registry."192.168.1.100"]
  insecure = true
EOF
```

### HTTPS 설정 (사설 인증서)

```bash
# 1. 인증서 패키지 압축 해제
tar -xzf harbor-certs-192.168.1.100.tar.gz

# 2. 인증서 설치
sudo make install-certs

# 3. Harbor 설정에서 HTTPS 활성화
cd /opt/harbor
sudo vi harbor.yml
# https 섹션 활성화 및 인증서 경로 설정

# 4. Harbor 재설치
sudo ./install.sh
```

### 클라이언트 시스템에 CA 추가

```bash
# Harbor CA를 클라이언트 시스템에 등록
sudo ./add-harbor-ca.sh ca.crt 192.168.1.100

# 또는 Makefile 사용
sudo make add-ca
```

## Makefile 주요 명령어

### 온라인 시스템
```bash
make help              # 도움말 표시
make download          # 패키지 다운로드
make generate-certs    # HTTPS 인증서 생성
make package           # 압축 패키지 생성
make quick-online      # 다운로드 + 패키징 (원클릭)
```

### 오프라인 시스템
```bash
make extract           # 패키지 압축 해제
make install           # Harbor 설치
make install-certs     # HTTPS 인증서 설치
make add-ca            # CA 인증서 시스템 등록
make verify            # 설치 확인
make quick-offline     # 압축 해제 + 설치 + 확인 (원클릭)
```

### Harbor 관리
```bash
make harbor-start      # Harbor 시작
make harbor-stop       # Harbor 중지
make harbor-restart    # Harbor 재시작
make harbor-status     # 상태 확인
make harbor-logs       # 로그 확인
make harbor-config     # 설정 예제 표시
```

### 유틸리티
```bash
make clean             # 다운로드 파일 정리
make info              # 시스템 정보 표시
make docs              # 문서 목록 표시
```

## 환경 변수 주요 설정 (.env)

```bash
# Harbor 기본 설정
HARBOR_VERSION=v2.11.1
HARBOR_HOSTNAME=192.168.1.100
HARBOR_ADMIN_PASSWORD=Harbor12345  # 반드시 변경!
HARBOR_DATA_VOLUME=/data

# HTTPS 설정
ENABLE_HTTPS=false
CERT_COUNTRY=KR
CERT_STATE=Seoul
CERT_VALIDITY_DAYS=3650

# 컨테이너 런타임
CONTAINER_RUNTIME=auto  # auto, docker, nerdctl
SKIP_DOCKER_INSTALL=false  # nerdctl 사용 시 true

# Kubernetes
USE_KUBERNETES=false  # K8s 배포는 false (registry로 사용)
K8S_NAMESPACE=harbor

# 시스템 설정
DISABLE_SELINUX=true
AUTO_CONFIGURE_FIREWALL=true
CREATE_SYSTEMD_SERVICE=true
```

전체 설정 옵션은 [env.example](env.example) 참조

## Kubernetes에서 Harbor 사용

### imagePullSecret 생성

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=192.168.1.100 \
  --docker-username=admin \
  --docker-password=<password> \
  --namespace=default
```

### Pod에서 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: 192.168.1.100/library/myapp:latest
  imagePullSecrets:
  - name: harbor-registry
```

자세한 내용은 [README-K8S.md](README-K8S.md) 참조

## 주요 스크립트 설명

### download-packages.sh
- Harbor offline installer 다운로드
- Docker, Docker Compose RPM 다운로드
- 의존성 패키지 다운로드
- .env 파일에서 버전 정보 로드

### create-package.sh
- 다운로드한 모든 파일을 단일 tar.gz로 압축
- MD5, SHA256 체크섬 생성
- 압축 해제 스크립트 자동 생성

### generate-certs.sh
- OpenSSL을 사용한 CA 및 서버 인증서 생성
- SAN (Subject Alternative Name) 지원
- Docker, containerd, nerdctl용 포맷 자동 변환
- 설치 스크립트 자동 생성

### add-harbor-ca.sh
- Harbor CA를 시스템 신뢰 저장소에 등록
- Docker, containerd, nerdctl, Podman 자동 설정
- RHEL/Ubuntu 모두 지원
- 클라이언트 시스템에서 재사용 가능

### install-harbor-nerdctl.sh
- nerdctl/containerd 환경에서 Harbor 설치
- Docker Compose 또는 nerdctl compose 자동 감지
- systemd 서비스 자동 생성
- 방화벽 자동 설정

## 사용 시나리오

### 시나리오 1: Docker 환경에서 HTTP 사용

```bash
# 온라인 시스템
make quick-online

# 오프라인 시스템
tar -xzf harbor-offline-rhel96-*.tar.gz
sudo make quick-offline

# 클라이언트에서 insecure registry 설정
sudo vi /etc/docker/daemon.json
{
  "insecure-registries": ["192.168.1.100"]
}
sudo systemctl restart docker
```

### 시나리오 2: nerdctl 환경에서 HTTPS 사용

```bash
# 온라인 시스템
vi .env  # ENABLE_HTTPS=true
make download
make generate-certs
make package

# 오프라인 시스템
tar -xzf harbor-offline-rhel96-*.tar.gz
tar -xzf harbor-certs-*.tar.gz

vi .env  # SKIP_DOCKER_INSTALL=true, ENABLE_HTTPS=true
cd harbor-offline-packages
sudo ./install-harbor-nerdctl.sh
sudo make add-ca
```

### 시나리오 3: K8s 설치 전 registry 준비

```bash
# 1. Harbor 설치 (시나리오 2와 동일)

# 2. K8s 노드에 CA 추가
sudo ./add-harbor-ca.sh ca.crt 192.168.1.100

# 3. K8s 설치 후 imagePullSecret 생성
kubectl create secret docker-registry harbor-registry \
  --docker-server=192.168.1.100 \
  --docker-username=admin \
  --docker-password=<password>

# 4. Harbor에 이미지 Push
nerdctl tag myimage:latest 192.168.1.100/library/myimage:latest
nerdctl push 192.168.1.100/library/myimage:latest

# 5. K8s에서 이미지 사용
kubectl run myapp --image=192.168.1.100/library/myimage:latest
```

## 장점

1. **완전 자동화**: 수동 작업 최소화, 실수 방지
2. **중앙 집중식 관리**: .env 파일로 모든 설정 관리
3. **유연성**: Docker/nerdctl 모두 지원, HTTP/HTTPS 선택 가능
4. **보안**: 사설 인증서 자동 생성 및 배포
5. **확장성**: 여러 클라이언트에 쉽게 배포
6. **K8s 친화적**: K8s 환경에서 바로 사용 가능

## 지원 환경

- **OS**: RHEL 9.6 (CentOS, Rocky Linux 등 호환 가능)
- **컨테이너 런타임**:
  - Docker 24.x+
  - containerd 1.6+
  - nerdctl 1.x+
- **아키텍처**: x86_64
- **Harbor 버전**: 2.11.x (설정 가능)

## 문서

- [README-KR.md](README-KR.md) - 상세 설치 가이드
- [QUICK-START-KR.md](QUICK-START-KR.md) - 빠른 시작 가이드
- [README-K8S.md](README-K8S.md) - Kubernetes 통합 가이드
- [env.example](env.example) - 환경 변수 설명
- [harbor-config-example.yml](harbor-config-example.yml) - Harbor 설정 예제

## 라이선스

이 프로젝트는 Harbor의 라이선스(Apache License 2.0)를 따릅니다.

## 참고 자료

- Harbor 공식 문서: https://goharbor.io/docs/
- Harbor GitHub: https://github.com/goharbor/harbor
- nerdctl GitHub: https://github.com/containerd/nerdctl
- containerd 문서: https://containerd.io/

---

**이 프로젝트를 사용하면 Harbor를 RHEL 9.6 오프라인 환경에서 빠르고 안전하게 설치하고, Kubernetes 클러스터의 private registry로 사용할 수 있습니다.**

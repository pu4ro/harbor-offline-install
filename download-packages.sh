#!/bin/bash

################################################################################
# Harbor 오프라인 설치를 위한 패키지 다운로드 스크립트
# 인터넷이 연결된 RHEL/CentOS 시스템에서 실행하세요
################################################################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# .env 파일 로드
if [ -f .env ]; then
    log_info ".env 파일 로드 중..."
    set -a
    source .env
    set +a
else
    log_warn ".env 파일이 없습니다. 기본값을 사용합니다."
    log_warn "env.example을 복사하여 .env를 생성하는 것을 권장합니다:"
    log_warn "  cp env.example .env"
    echo ""
fi

# 버전 설정 (.env 파일에서 설정하지 않은 경우 기본값 사용)
HARBOR_VERSION="${HARBOR_VERSION:-v2.11.1}"
DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-v2.24.5}"

# 작업 디렉토리 생성
DOWNLOAD_DIR="${PACKAGE_DIR:-harbor-offline-packages}"
log_info "작업 디렉토리 생성: $DOWNLOAD_DIR"
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR

# 1. Harbor 오프라인 설치 패키지 다운로드
log_info "Harbor 오프라인 설치 패키지 다운로드 중..."
HARBOR_OFFLINE_FILE="harbor-offline-installer-${HARBOR_VERSION}.tgz"
HARBOR_DOWNLOAD_URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${HARBOR_OFFLINE_FILE}"

if [ ! -f "$HARBOR_OFFLINE_FILE" ]; then
    log_info "다운로드: $HARBOR_DOWNLOAD_URL"
    wget -c $HARBOR_DOWNLOAD_URL || curl -LO $HARBOR_DOWNLOAD_URL
    log_info "Harbor 오프라인 패키지 다운로드 완료"
else
    log_warn "Harbor 패키지가 이미 존재합니다. 건너뜁니다."
fi

# 2. Docker Compose 다운로드
log_info "Docker Compose 다운로드 중..."
COMPOSE_FILE="docker-compose-linux-x86_64"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64"

if [ ! -f "$COMPOSE_FILE" ]; then
    log_info "다운로드: $COMPOSE_URL"
    wget -c $COMPOSE_URL -O $COMPOSE_FILE || curl -L $COMPOSE_URL -o $COMPOSE_FILE
    chmod +x $COMPOSE_FILE
    log_info "Docker Compose 다운로드 완료"
else
    log_warn "Docker Compose가 이미 존재합니다. 건너뜁니다."
fi

# 3. Docker 및 의존성 RPM 패키지 다운로드
log_info "Docker 및 의존성 RPM 패키지 다운로드 중..."
mkdir -p rpms
cd rpms

# Docker 저장소 설정
log_info "Docker 저장소 설정 중..."

# Docker 공식 저장소 추가
if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
fi

# 필요한 패키지 목록
PACKAGES=(
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-buildx-plugin"
    "docker-compose-plugin"
)

# 각 패키지와 의존성 다운로드
log_info "패키지 다운로드 시작..."
for package in "${PACKAGES[@]}"; do
    log_info "다운로드 중: $package"
    sudo yumdownloader --resolve --destdir=. $package 2>/dev/null || true
done

# 추가 의존성 다운로드 (RHEL 9.6용)
log_info "추가 의존성 다운로드 중..."
sudo yumdownloader --resolve --destdir=. \
    libcgroup \
    libcgroup-tools \
    fuse-overlayfs \
    slirp4netns \
    container-selinux \
    policycoreutils-python-utils \
    2>/dev/null || true

cd ..

# 4. 설치 스크립트 복사
log_info "설치 스크립트 생성 중..."
cat > install-offline.sh << 'INSTALL_SCRIPT_EOF'
#!/bin/bash

################################################################################
# Harbor 오프라인 설치 스크립트 (RHEL 9.6)
################################################################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한으로 실행해야 합니다."
    exit 1
fi

log_info "Harbor 오프라인 설치를 시작합니다..."

# 1. RPM 패키지 설치
log_info "Docker 및 의존성 패키지 설치 중..."
cd rpms
rpm -Uvh --force --nodeps *.rpm || yum localinstall -y *.rpm
cd ..

log_info "Docker 패키지 설치 완료"

# 2. Docker 서비스 시작
log_info "Docker 서비스 시작 중..."
systemctl enable docker
systemctl start docker
systemctl status docker --no-pager

# 3. Docker Compose 설치
log_info "Docker Compose 설치 중..."
cp docker-compose-linux-x86_64 /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Docker Compose 버전 확인
docker-compose --version

# 4. Harbor 압축 해제
log_info "Harbor 설치 파일 압축 해제 중..."
HARBOR_FILE=$(ls harbor-offline-installer-*.tgz | head -1)
tar xzvf $HARBOR_FILE -C /opt/

log_info "Harbor 파일이 /opt/harbor에 압축 해제되었습니다."

# 5. 방화벽 설정 (firewalld가 실행 중인 경우)
if systemctl is-active --quiet firewalld; then
    log_info "방화벽 규칙 추가 중..."
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    log_info "방화벽 규칙 추가 완료"
fi

log_info ""
log_info "=========================================="
log_info "오프라인 설치가 완료되었습니다!"
log_info "=========================================="
log_info ""
log_info "다음 단계:"
log_info "1. cd /opt/harbor"
log_info "2. cp harbor.yml.tmpl harbor.yml"
log_info "3. vi harbor.yml (설정 파일 편집)"
log_info "   - hostname을 서버 IP 또는 도메인으로 변경"
log_info "   - harbor_admin_password 변경"
log_info "4. ./install.sh"
log_info ""
log_info "자세한 내용은 README-KR.md를 참조하세요."
log_info ""

INSTALL_SCRIPT_EOF

chmod +x install-offline.sh

# 5. README 파일 복사 (상위 디렉토리에 있는 경우)
if [ -f ../README-KR.md ]; then
    cp ../README-KR.md .
    log_info "README-KR.md 복사 완료"
fi

# 6. 검증 스크립트 생성
cat > verify-installation.sh << 'VERIFY_SCRIPT_EOF'
#!/bin/bash

################################################################################
# Harbor 설치 검증 스크립트
################################################################################

echo "=========================================="
echo "Harbor 설치 검증"
echo "=========================================="
echo ""

# Docker 확인
echo "1. Docker 버전 확인:"
docker --version
echo ""

# Docker Compose 확인
echo "2. Docker Compose 버전 확인:"
docker-compose --version
echo ""

# Docker 서비스 상태 확인
echo "3. Docker 서비스 상태:"
systemctl status docker --no-pager | head -5
echo ""

# Harbor 설치 확인
if [ -d "/opt/harbor" ]; then
    echo "4. Harbor 설치 디렉토리: 존재함 (/opt/harbor)"

    # Harbor 컨테이너 상태 확인
    if command -v docker-compose &> /dev/null; then
        cd /opt/harbor
        echo ""
        echo "5. Harbor 컨테이너 상태:"
        docker-compose ps 2>/dev/null || echo "Harbor가 아직 시작되지 않았습니다."
    fi
else
    echo "4. Harbor 설치 디렉토리: 존재하지 않음"
    echo "   Harbor를 먼저 설치하세요."
fi

echo ""
echo "=========================================="
echo "검증 완료"
echo "=========================================="

VERIFY_SCRIPT_EOF

chmod +x verify-installation.sh

# 7. Harbor 설정 가이드 생성
cat > INSTALL-GUIDE-KR.txt << 'GUIDE_EOF'
================================================================================
Harbor 오프라인 설치 가이드 (RHEL 9.6)
================================================================================

이 패키지를 RHEL 9.6 오프라인 시스템으로 전송한 후 아래 단계를 따르세요.

================================================================================
1단계: 오프라인 설치 스크립트 실행
================================================================================

sudo ./install-offline.sh

이 스크립트는 다음을 수행합니다:
- Docker 및 필요한 RPM 패키지 설치
- Docker Compose 설치
- Harbor 압축 해제 (/opt/harbor)
- 방화벽 규칙 설정

================================================================================
2단계: Harbor 설정
================================================================================

cd /opt/harbor
cp harbor.yml.tmpl harbor.yml
vi harbor.yml

다음 항목을 반드시 수정하세요:

1. hostname: 서버의 IP 주소 또는 도메인 이름
   hostname: 192.168.1.100

2. harbor_admin_password: 관리자 비밀번호
   harbor_admin_password: YourSecurePassword123!

3. (선택) HTTPS 설정 - 인증서가 있는 경우
   https:
     port: 443
     certificate: /path/to/cert.crt
     private_key: /path/to/cert.key

HTTP만 사용하는 경우 HTTPS 섹션을 주석 처리하세요.

================================================================================
3단계: Harbor 설치 및 시작
================================================================================

cd /opt/harbor
sudo ./install.sh

또는 추가 구성 요소와 함께 설치:

sudo ./install.sh --with-trivy --with-chartmuseum

설치가 완료되면 모든 Harbor 서비스가 자동으로 시작됩니다.

================================================================================
4단계: 설치 확인
================================================================================

# 컨테이너 상태 확인
docker-compose ps

# 또는 검증 스크립트 실행
./verify-installation.sh

# 웹 브라우저에서 접속
http://your-server-ip

기본 로그인:
- 사용자명: admin
- 비밀번호: harbor.yml에서 설정한 비밀번호

================================================================================
5단계: Docker 클라이언트 설정 (HTTP 사용 시)
================================================================================

Harbor를 HTTP로 설정한 경우, Docker 클라이언트에서 insecure registry로 추가:

# /etc/docker/daemon.json 편집
sudo vi /etc/docker/daemon.json

다음 내용 추가:
{
  "insecure-registries": ["your-harbor-ip"]
}

# Docker 재시작
sudo systemctl restart docker

# Harbor에 로그인
docker login your-harbor-ip

================================================================================
Harbor 서비스 관리
================================================================================

cd /opt/harbor

# 중지
sudo docker-compose down

# 시작
sudo docker-compose up -d

# 재시작
sudo docker-compose restart

# 로그 확인
sudo docker-compose logs -f

================================================================================
문제 해결
================================================================================

1. SELinux 문제가 발생하는 경우:
   sudo setenforce 0

2. 방화벽 문제:
   sudo firewall-cmd --list-all
   sudo firewall-cmd --permanent --add-port=80/tcp
   sudo firewall-cmd --permanent --add-port=443/tcp
   sudo firewall-cmd --reload

3. 디스크 공간 확인:
   df -h

4. Docker 로그 확인:
   sudo journalctl -u docker -f

자세한 내용은 README-KR.md 파일을 참조하세요.

================================================================================
GUIDE_EOF

cd ..

# 8. 다운로드 요약 출력
log_info ""
log_info "=========================================="
log_info "다운로드 완료!"
log_info "=========================================="
log_info ""
log_info "다운로드된 파일:"
log_info "- $DOWNLOAD_DIR/"
log_info "  ├── harbor-offline-installer-${HARBOR_VERSION}.tgz"
log_info "  ├── docker-compose-linux-x86_64"
log_info "  ├── rpms/ (Docker 및 의존성 패키지)"
log_info "  ├── install-offline.sh"
log_info "  ├── verify-installation.sh"
log_info "  ├── INSTALL-GUIDE-KR.txt"
log_info "  └── README-KR.md (있는 경우)"
log_info ""
log_info "다음 단계:"
log_info "1. 패키징 스크립트를 실행하여 단일 파일로 압축:"
log_info "   ./create-package.sh"
log_info ""
log_info "2. 생성된 패키지를 오프라인 시스템으로 전송"
log_info ""
log_info "3. 오프라인 시스템에서 압축 해제 후 install-offline.sh 실행"
log_info ""

log_info "다운로드 위치: $(pwd)/$DOWNLOAD_DIR"

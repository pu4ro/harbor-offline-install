#!/bin/bash

################################################################################
# Harbor 오프라인 설치를 위한 패키지 다운로드 스크립트
# nerdctl/containerd 기반 (Docker 제외)
# 인터넷이 연결된 시스템에서 실행하세요
################################################################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo "$1"
    echo -e "==========================================${NC}"
}

# .env 파일 로드
if [ -f .env ]; then
    log_info ".env 파일 로드 중..."
    set -a
    source .env
    set +a
else
    log_warn ".env 파일이 없습니다. 기본값을 사용합니다."
    log_warn "권장: cp env.example .env"
    echo ""
fi

# 버전 설정
HARBOR_VERSION="${HARBOR_VERSION:-v2.11.1}"
DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-v2.24.5}"

# 작업 디렉토리 생성
DOWNLOAD_DIR="${PACKAGE_DIR:-harbor-offline-packages}"
log_info "작업 디렉토리: $DOWNLOAD_DIR"
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR

log_section "Harbor 오프라인 패키지 다운로드"

# 1. Harbor 오프라인 설치 패키지
log_info "Harbor ${HARBOR_VERSION} 다운로드 중..."
HARBOR_OFFLINE_FILE="harbor-offline-installer-${HARBOR_VERSION}.tgz"
HARBOR_DOWNLOAD_URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${HARBOR_OFFLINE_FILE}"

if [ ! -f "$HARBOR_OFFLINE_FILE" ]; then
    log_info "다운로드: $HARBOR_DOWNLOAD_URL"
    if command -v wget &> /dev/null; then
        wget -c $HARBOR_DOWNLOAD_URL
    else
        curl -LO $HARBOR_DOWNLOAD_URL
    fi
    log_info "✓ Harbor 패키지 다운로드 완료"
else
    log_warn "Harbor 패키지가 이미 존재합니다."
fi

# 2. Docker Compose (nerdctl compose 대신 사용)
log_info "Docker Compose ${DOCKER_COMPOSE_VERSION} 다운로드 중..."
COMPOSE_FILE="docker-compose-linux-x86_64"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64"

if [ ! -f "$COMPOSE_FILE" ]; then
    log_info "다운로드: $COMPOSE_URL"
    if command -v wget &> /dev/null; then
        wget -c $COMPOSE_URL -O $COMPOSE_FILE
    else
        curl -L $COMPOSE_URL -o $COMPOSE_FILE
    fi
    chmod +x $COMPOSE_FILE
    log_info "✓ Docker Compose 다운로드 완료"
else
    log_warn "Docker Compose가 이미 존재합니다."
fi

log_section "설치 스크립트 생성"

# 3. 오프라인 설치 스크립트 생성
cat > install-offline.sh << 'INSTALL_SCRIPT'
#!/bin/bash

################################################################################
# Harbor 오프라인 설치 스크립트 (nerdctl 전용)
# nerdctl과 containerd는 시스템 repo에서 설치됨
################################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다."
    exit 1
fi

log_info "Harbor 오프라인 설치 시작..."

# 1. nerdctl 및 containerd 확인
log_info "nerdctl 및 containerd 확인 중..."
if ! command -v nerdctl &> /dev/null; then
    log_error "nerdctl이 설치되어 있지 않습니다."
    log_info "설치 방법: dnf install -y nerdctl"
    exit 1
fi

if ! systemctl is-active --quiet containerd; then
    log_warn "containerd가 실행 중이지 않습니다. 시작합니다..."
    systemctl enable --now containerd
fi

log_info "✓ nerdctl: $(nerdctl --version | head -1)"
log_info "✓ containerd: 실행 중"

# 2. Docker Compose 설치
log_info "Docker Compose 설치 중..."
if [ -f "docker-compose-linux-x86_64" ]; then
    cp docker-compose-linux-x86_64 /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    log_info "✓ Docker Compose 설치 완료: $(docker-compose --version)"
else
    log_error "docker-compose-linux-x86_64 파일을 찾을 수 없습니다."
    exit 1
fi

# 3. Harbor 압축 해제
log_info "Harbor 패키지 압축 해제 중..."
HARBOR_FILE=$(ls harbor-offline-installer-*.tgz 2>/dev/null | head -1)
if [ -z "$HARBOR_FILE" ]; then
    log_error "Harbor 설치 파일을 찾을 수 없습니다."
    exit 1
fi

tar -xzf $HARBOR_FILE -C /opt/
log_info "✓ Harbor 압축 해제 완료: /opt/harbor"

# 4. Harbor 이미지 로드 (nerdctl 사용)
log_info "Harbor 이미지 로드 중..."
cd /opt/harbor
if [ -f "harbor.v*.tar.gz" ]; then
    HARBOR_IMAGES_FILE=$(ls harbor.v*.tar.gz)
    log_info "이미지 파일: $HARBOR_IMAGES_FILE"
    nerdctl load -i $HARBOR_IMAGES_FILE
    log_info "✓ Harbor 이미지 로드 완료"
else
    log_error "Harbor 이미지 파일을 찾을 수 없습니다."
    exit 1
fi

log_info ""
log_info "=========================================="
log_info "✓ Harbor 오프라인 설치 완료!"
log_info "=========================================="
log_info ""
log_info "다음 단계:"
log_info "  1. cd /opt/harbor"
log_info "  2. cp harbor.yml.tmpl harbor.yml"
log_info "  3. vi harbor.yml  # hostname, 비밀번호 설정"
log_info "  4. ./prepare"
log_info "  5. nerdctl compose up -d"
log_info ""
log_info "또는 자동 설치:"
log_info "  cd /root/harbor-offline-install"
log_info "  ./install-harbor-nerdctl.sh"
log_info ""
INSTALL_SCRIPT

chmod +x install-offline.sh
log_info "✓ 설치 스크립트 생성: install-offline.sh"

# 4. 검증 스크립트 생성
cat > verify-installation.sh << 'VERIFY_SCRIPT'
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Harbor 설치 검증 중..."
echo ""

# nerdctl 확인
if command -v nerdctl &> /dev/null; then
    echo -e "${GREEN}✓${NC} nerdctl: $(nerdctl --version | head -1)"
else
    echo -e "${RED}✗${NC} nerdctl이 설치되어 있지 않습니다."
fi

# containerd 확인
if systemctl is-active --quiet containerd; then
    echo -e "${GREEN}✓${NC} containerd: 실행 중"
else
    echo -e "${RED}✗${NC} containerd가 실행 중이지 않습니다."
fi

# docker-compose 확인
if command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓${NC} docker-compose: $(docker-compose --version)"
else
    echo -e "${YELLOW}⚠${NC} docker-compose가 설치되어 있지 않습니다."
fi

# Harbor 디렉토리 확인
if [ -d "/opt/harbor" ]; then
    echo -e "${GREEN}✓${NC} Harbor 디렉토리: /opt/harbor"
else
    echo -e "${YELLOW}⚠${NC} Harbor가 아직 설치되지 않았습니다."
fi

echo ""
echo "검증 완료!"
VERIFY_SCRIPT

chmod +x verify-installation.sh
log_info "✓ 검증 스크립트 생성: verify-installation.sh"

# 5. README 파일 복사
log_info "문서 파일 복사 중..."
if [ -f "../README-KR.md" ]; then
    cp ../README-KR.md .
fi
if [ -f "../QUICKSTART.md" ]; then
    cp ../QUICKSTART.md INSTALL-GUIDE.txt
fi

cd ..

log_section "다운로드 완료"

echo ""
log_info "다운로드된 파일:"
echo "  - Harbor: $HARBOR_OFFLINE_FILE"
echo "  - Docker Compose: $COMPOSE_FILE"
echo "  - 설치 스크립트: install-offline.sh"
echo ""
log_info "디렉토리 크기: $(du -sh $DOWNLOAD_DIR | cut -f1)"
echo ""
log_info "다음 단계:"
echo "  1. make package  # 단일 패키지로 압축"
echo "  2. 오프라인 시스템으로 전송"
echo "  3. make extract  # 압축 해제"
echo "  4. sudo make install  # 설치"
echo ""

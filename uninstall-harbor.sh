#!/bin/bash

################################################################################
# Harbor 완전 제거 스크립트
# Harbor 컨테이너, 데이터, 설정 파일을 모두 삭제합니다
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

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한으로 실행해야 합니다."
    exit 1
fi

log_section "Harbor 제거 시작"

# .env 파일 로드 (선택적)
if [ -f .env ]; then
    log_info ".env 파일 로드 중..."
    set -a
    source .env 2>/dev/null || true
    set +a
fi

# 기본 설정
HARBOR_DATA_VOLUME="${HARBOR_DATA_VOLUME:-/data}"

log_info ""
log_warn "경고: 다음 항목들이 삭제됩니다:"
log_warn "  - Harbor 컨테이너"
log_warn "  - Harbor 데이터 (/data)"
log_warn "  - Harbor 설치 디렉토리 (/opt/harbor)"
log_warn "  - Harbor systemd 서비스"
echo ""
read -p "계속하시겠습니까? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
    log_info "제거 취소됨"
    exit 0
fi

# 1. Harbor 컨테이너 중지 및 삭제
log_info "Step 1/5: Harbor 컨테이너 중지 및 삭제 중..."
if [ -d "/opt/harbor" ]; then
    cd /opt/harbor

    # nerdctl compose 사용
    if command -v nerdctl &> /dev/null; then
        log_info "nerdctl compose를 사용하여 컨테이너 중지 중..."
        nerdctl compose down -v 2>/dev/null || true
    fi

    # docker-compose 사용 (있는 경우)
    if command -v docker-compose &> /dev/null; then
        log_info "docker-compose를 사용하여 컨테이너 중지 중..."
        docker-compose down -v 2>/dev/null || true
    fi

    log_info "✓ Harbor 컨테이너 중지 완료"
else
    log_warn "Harbor 설치 디렉토리가 없습니다. 건너뜁니다."
fi

# 2. Harbor systemd 서비스 중지 및 삭제
log_info ""
log_info "Step 2/5: Harbor systemd 서비스 제거 중..."
if systemctl is-enabled harbor &> /dev/null; then
    log_info "Harbor 서비스 중지 및 비활성화 중..."
    systemctl stop harbor 2>/dev/null || true
    systemctl disable harbor 2>/dev/null || true
    log_info "✓ Harbor 서비스 중지 및 비활성화 완료"
fi

if [ -f "/etc/systemd/system/harbor.service" ]; then
    log_info "Harbor systemd 서비스 파일 삭제 중..."
    rm -f /etc/systemd/system/harbor.service
    systemctl daemon-reload
    log_info "✓ Harbor systemd 서비스 파일 삭제 완료"
else
    log_warn "Harbor systemd 서비스 파일이 없습니다. 건너뜁니다."
fi

# 3. Harbor 설치 디렉토리 삭제
log_info ""
log_info "Step 3/5: Harbor 설치 디렉토리 삭제 중..."
if [ -d "/opt/harbor" ]; then
    log_info "Harbor 설치 디렉토리 삭제: /opt/harbor"
    rm -rf /opt/harbor
    log_info "✓ Harbor 설치 디렉토리 삭제 완료"
else
    log_warn "Harbor 설치 디렉토리가 없습니다. 건너뜁니다."
fi

# 4. Harbor 데이터 디렉토리 삭제
log_info ""
log_info "Step 4/5: Harbor 데이터 디렉토리 삭제 중..."
if [ -d "$HARBOR_DATA_VOLUME" ]; then
    log_warn "Harbor 데이터 디렉토리 삭제: $HARBOR_DATA_VOLUME"
    log_warn "이 작업은 모든 이미지, 프로젝트, 로그를 삭제합니다."
    read -p "정말로 데이터를 삭제하시겠습니까? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy](es)?$ ]]; then
        rm -rf $HARBOR_DATA_VOLUME
        log_info "✓ Harbor 데이터 디렉토리 삭제 완료"
    else
        log_info "데이터 디렉토리 삭제 건너뜀"
    fi
else
    log_warn "Harbor 데이터 디렉토리가 없습니다. 건너뜁니다."
fi

# 5. Docker 심볼릭 링크 제거 (선택적)
log_info ""
log_info "Step 5/5: Docker 심볼릭 링크 확인 중..."
if [ -L "/usr/local/bin/docker" ]; then
    LINK_TARGET=$(readlink -f /usr/local/bin/docker 2>/dev/null || true)
    if [[ "$LINK_TARGET" == *"nerdctl"* ]]; then
        log_info "Docker -> nerdctl 심볼릭 링크 발견"
        read -p "Docker 심볼릭 링크를 제거하시겠습니까? (yes/no): " -r
        echo
        if [[ $REPLY =~ ^[Yy](es)?$ ]]; then
            rm -f /usr/local/bin/docker
            log_info "✓ Docker 심볼릭 링크 제거 완료"
        else
            log_info "Docker 심볼릭 링크 제거 건너뜀"
        fi
    fi
fi

log_section "Harbor 제거 완료"

log_info ""
log_info "Harbor가 성공적으로 제거되었습니다."
log_info ""
log_info "제거된 항목:"
log_info "  ✓ Harbor 컨테이너"
log_info "  ✓ Harbor systemd 서비스"
log_info "  ✓ Harbor 설치 디렉토리 (/opt/harbor)"
if [ ! -d "$HARBOR_DATA_VOLUME" ]; then
    log_info "  ✓ Harbor 데이터 디렉토리 ($HARBOR_DATA_VOLUME)"
fi
log_info ""
log_info "필요시 재설치 방법:"
log_info "  cd harbor-offline-install"
log_info "  sudo make harbor-auto-install"
log_info ""

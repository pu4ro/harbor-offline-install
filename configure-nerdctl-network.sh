#!/bin/bash

################################################################################
# nerdctl CNI 브리지 네트워크 설정 스크립트
# /etc/cni/net.d/nerdctl-bridge.conflist 파일을 생성합니다
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

log_section "nerdctl CNI 네트워크 설정"

# .env 파일 로드
if [ -f .env ]; then
    log_info ".env 파일 로드 중..."
    set -a
    source .env
    set +a
else
    log_error ".env 파일이 없습니다."
    log_error "실행: cp env.example .env && vi .env"
    exit 1
fi

# 기본값 설정
ENABLE_NERDCTL_CUSTOM_NETWORK="${ENABLE_NERDCTL_CUSTOM_NETWORK:-false}"
NERDCTL_NETWORK_SUBNET="${NERDCTL_NETWORK_SUBNET:-192.168.100.0/24}"
NERDCTL_NETWORK_GATEWAY="${NERDCTL_NETWORK_GATEWAY:-192.168.100.1}"
NERDCTL_BRIDGE_NAME="${NERDCTL_BRIDGE_NAME:-nerdctl0}"

# nerdctl 설치 확인
if ! command -v nerdctl &> /dev/null; then
    log_error "nerdctl이 설치되어 있지 않습니다."
    log_error "설치: dnf install -y nerdctl"
    exit 1
fi

# CNI 플러그인 확인
CNI_BIN_DIR="/opt/cni/bin"
if [ ! -d "$CNI_BIN_DIR" ] || [ ! -f "$CNI_BIN_DIR/bridge" ]; then
    log_warn "CNI 플러그인이 설치되어 있지 않습니다."
    log_warn "설치 방법:"
    log_warn "  dnf install -y containernetworking-plugins"
    log_warn "또는"
    log_warn "  https://github.com/containernetworking/plugins/releases에서 다운로드"
fi

# ENABLE_NERDCTL_CUSTOM_NETWORK 확인
if [ "$ENABLE_NERDCTL_CUSTOM_NETWORK" != "true" ]; then
    log_warn "ENABLE_NERDCTL_CUSTOM_NETWORK=false입니다."
    log_info "nerdctl 기본 네트워크를 사용합니다."
    log_info ""
    log_info "사용자 정의 네트워크를 설정하려면:"
    log_info "  1. vi .env"
    log_info "  2. ENABLE_NERDCTL_CUSTOM_NETWORK=true로 설정"
    log_info "  3. sudo ./configure-nerdctl-network.sh 재실행"
    exit 0
fi

log_info ""
log_info "nerdctl CNI 네트워크 설정:"
log_info "  서브넷: ${NERDCTL_NETWORK_SUBNET}"
log_info "  게이트웨이: ${NERDCTL_NETWORK_GATEWAY}"
log_info "  브리지: ${NERDCTL_BRIDGE_NAME}"
echo ""

# CNI 설정 디렉토리 생성
CNI_CONFIG_DIR="/etc/cni/net.d"
log_info "CNI 설정 디렉토리 생성: $CNI_CONFIG_DIR"
mkdir -p $CNI_CONFIG_DIR

# 기존 nerdctl-bridge.conflist 백업
CONFLIST_FILE="$CNI_CONFIG_DIR/nerdctl-bridge.conflist"
if [ -f "$CONFLIST_FILE" ]; then
    BACKUP_FILE="${CONFLIST_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    log_warn "기존 설정 파일 발견. 백업 생성..."
    cp "$CONFLIST_FILE" "$BACKUP_FILE"
    log_info "백업: $BACKUP_FILE"
fi

# nerdctlID 생성 (고유 ID)
NERDCTL_ID=$(cat /proc/sys/kernel/random/uuid | sha256sum | awk '{print $1}')

# nerdctl-bridge.conflist 생성
log_info ""
log_info "nerdctl-bridge.conflist 생성 중..."

cat > "$CONFLIST_FILE" <<EOF
{
  "cniVersion": "1.0.0",
  "name": "bridge",
  "nerdctlID": "${NERDCTL_ID}",
  "nerdctlLabels": {
    "nerdctl/default-network": "true"
  },
  "plugins": [
    {
      "type": "bridge",
      "bridge": "${NERDCTL_BRIDGE_NAME}",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": {
        "ranges": [
          [
            {
              "gateway": "${NERDCTL_NETWORK_GATEWAY}",
              "subnet": "${NERDCTL_NETWORK_SUBNET}"
            }
          ]
        ],
        "routes": [
          {
            "dst": "0.0.0.0/0"
          }
        ],
        "type": "host-local"
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    },
    {
      "type": "firewall",
      "ingressPolicy": "same-bridge"
    },
    {
      "type": "tuning"
    }
  ]
}
EOF

log_info "✓ nerdctl-bridge.conflist 생성 완료"

# 파일 권한 설정
chmod 644 "$CONFLIST_FILE"

# 설정 파일 내용 확인
log_info ""
log_info "생성된 설정 파일:"
log_info "=========================================="
cat "$CONFLIST_FILE"
log_info "=========================================="

# containerd 재시작 (필요한 경우)
if systemctl is-active --quiet containerd; then
    log_info ""
    read -p "containerd를 재시작하시겠습니까? (y/n) [n]: " RESTART_CONTAINERD
    RESTART_CONTAINERD=${RESTART_CONTAINERD:-n}

    if [[ $RESTART_CONTAINERD =~ ^[Yy]$ ]]; then
        log_info "containerd 재시작 중..."
        systemctl restart containerd
        log_info "✓ containerd 재시작 완료"
    else
        log_warn "containerd를 재시작하지 않았습니다."
        log_warn "변경사항을 적용하려면 수동으로 재시작하세요:"
        log_warn "  systemctl restart containerd"
    fi
fi

log_section "nerdctl 네트워크 설정 완료"

log_info ""
log_info "설정 파일: $CONFLIST_FILE"
log_info "네트워크 정보:"
log_info "  - 이름: bridge"
log_info "  - 서브넷: ${NERDCTL_NETWORK_SUBNET}"
log_info "  - 게이트웨이: ${NERDCTL_NETWORK_GATEWAY}"
log_info "  - 브리지: ${NERDCTL_BRIDGE_NAME}"
log_info ""
log_info "테스트:"
log_info "  nerdctl network ls"
log_info "  nerdctl network inspect bridge"
log_info ""
log_info "컨테이너 실행 시 이 네트워크가 기본으로 사용됩니다."
log_info ""

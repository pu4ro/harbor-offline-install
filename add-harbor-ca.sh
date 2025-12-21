#!/bin/bash

################################################################################
# Harbor CA 인증서를 시스템에 추가하는 스크립트
# insecure registry 문제를 해결하고 HTTPS를 안전하게 사용
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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한으로 실행해야 합니다."
    echo "사용법: sudo $0 <ca.crt 파일 경로> <harbor-hostname>"
    exit 1
fi

# 사용법 출력
usage() {
    echo ""
    echo "사용법:"
    echo "  $0 <CA 인증서 파일> <Harbor 호스트명>"
    echo ""
    echo "예제:"
    echo "  $0 ca.crt 192.168.1.100"
    echo "  $0 /path/to/ca.crt harbor.example.com"
    echo ""
    exit 1
}

# 인자 확인
if [ $# -lt 2 ]; then
    log_error "인자가 부족합니다."
    usage
fi

CA_CERT_FILE="$1"
HARBOR_HOSTNAME="$2"

# CA 인증서 파일 확인
if [ ! -f "$CA_CERT_FILE" ]; then
    log_error "CA 인증서 파일을 찾을 수 없습니다: $CA_CERT_FILE"
    exit 1
fi

log_info ""
log_info "=========================================="
log_info "Harbor CA 인증서 시스템 등록"
log_info "=========================================="
log_info ""
log_info "CA 인증서: $CA_CERT_FILE"
log_info "Harbor 호스트: $HARBOR_HOSTNAME"
log_info ""

# 1. 시스템 CA 신뢰 저장소에 추가
log_info "Step 1/5: 시스템 CA 신뢰 저장소에 추가 중..."

# OS 종류 확인
if [ -f /etc/redhat-release ]; then
    # RHEL/CentOS/Fedora
    OS_TYPE="rhel"
    CA_TRUST_DIR="/etc/pki/ca-trust/source/anchors"
    UPDATE_CMD="update-ca-trust"
elif [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    OS_TYPE="debian"
    CA_TRUST_DIR="/usr/local/share/ca-certificates"
    UPDATE_CMD="update-ca-certificates"
else
    log_warn "알 수 없는 OS입니다. RHEL 방식으로 시도합니다."
    OS_TYPE="rhel"
    CA_TRUST_DIR="/etc/pki/ca-trust/source/anchors"
    UPDATE_CMD="update-ca-trust"
fi

log_info "OS 종류: $OS_TYPE"
log_info "CA 신뢰 디렉토리: $CA_TRUST_DIR"

# CA 인증서 복사
mkdir -p $CA_TRUST_DIR

if [ "$OS_TYPE" = "debian" ]; then
    # Debian/Ubuntu는 .crt 확장자 필요
    cp "$CA_CERT_FILE" "$CA_TRUST_DIR/harbor-ca.crt"
else
    cp "$CA_CERT_FILE" "$CA_TRUST_DIR/harbor-ca.crt"
fi

# CA 신뢰 저장소 업데이트
log_info "CA 신뢰 저장소 업데이트 중..."
$UPDATE_CMD

log_success "시스템 CA 신뢰 저장소에 Harbor CA 추가 완료"

# 2. Docker 설정 (Docker가 설치된 경우)
log_info ""
log_info "Step 2/5: Docker 설정 중..."

if command -v docker &> /dev/null; then
    DOCKER_CERT_DIR="/etc/docker/certs.d/${HARBOR_HOSTNAME}"

    log_info "Docker 인증서 디렉토리 생성: $DOCKER_CERT_DIR"
    mkdir -p $DOCKER_CERT_DIR

    # CA 인증서 복사
    cp "$CA_CERT_FILE" "$DOCKER_CERT_DIR/ca.crt"

    log_success "Docker 설정 완료"

    # Docker 재시작 여부 확인
    if systemctl is-active --quiet docker; then
        read -p "Docker를 재시작하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl restart docker
            log_success "Docker 재시작 완료"
        else
            log_warn "변경사항 적용을 위해 나중에 Docker를 재시작하세요: systemctl restart docker"
        fi
    fi
else
    log_warn "Docker가 설치되어 있지 않습니다. 건너뜁니다."
fi

# 3. containerd 설정 (containerd가 설치된 경우)
log_info ""
log_info "Step 3/5: containerd 설정 중..."

if command -v containerd &> /dev/null; then
    CONTAINERD_CERT_DIR="/etc/containerd/certs.d/${HARBOR_HOSTNAME}"

    log_info "containerd 인증서 디렉토리 생성: $CONTAINERD_CERT_DIR"
    mkdir -p $CONTAINERD_CERT_DIR

    # CA 인증서 복사
    cp "$CA_CERT_FILE" "$CONTAINERD_CERT_DIR/ca.crt"

    # containerd hosts.toml 생성
    cat > "$CONTAINERD_CERT_DIR/hosts.toml" <<EOF
server = "https://${HARBOR_HOSTNAME}"

[host."https://${HARBOR_HOSTNAME}"]
  ca = "${CONTAINERD_CERT_DIR}/ca.crt"
  skip_verify = false
EOF

    log_success "containerd 설정 완료"

    # containerd 재시작 여부 확인
    if systemctl is-active --quiet containerd; then
        read -p "containerd를 재시작하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl restart containerd
            log_success "containerd 재시작 완료"
        else
            log_warn "변경사항 적용을 위해 나중에 containerd를 재시작하세요: systemctl restart containerd"
        fi
    fi
else
    log_warn "containerd가 설치되어 있지 않습니다. 건너뜁니다."
fi

# 4. nerdctl 설정
log_info ""
log_info "Step 4/5: nerdctl 설정 확인 중..."
log_info "nerdctl은 containerd의 hosts.toml을 사용하므로 별도 설정이 필요없습니다."

# 기존 nerdctl.toml이 있으면 삭제 (containerd hosts.toml 사용)
if command -v nerdctl &> /dev/null; then
    NERDCTL_TOML="/etc/nerdctl/nerdctl.toml"

    if [ -f "$NERDCTL_TOML" ]; then
        log_warn "기존 nerdctl.toml 발견. 삭제 중..."
        rm -f "$NERDCTL_TOML"
        log_success "nerdctl.toml 삭제 완료 (containerd hosts.toml 사용)"
    else
        log_info "nerdctl.toml 없음 (정상)"
    fi
fi

# 5. Podman 설정 (Podman이 설치된 경우)
log_info ""
log_info "Step 5/5: Podman 설정 중..."

if command -v podman &> /dev/null; then
    PODMAN_CERT_DIR="/etc/containers/certs.d/${HARBOR_HOSTNAME}"

    log_info "Podman 인증서 디렉토리 생성: $PODMAN_CERT_DIR"
    mkdir -p $PODMAN_CERT_DIR

    # CA 인증서 복사
    cp "$CA_CERT_FILE" "$PODMAN_CERT_DIR/ca.crt"

    log_success "Podman 설정 완료"
else
    log_warn "Podman이 설치되어 있지 않습니다. 건너뜁니다."
fi

# 6. 설정 확인
log_info ""
log_info "=========================================="
log_info "설정 확인"
log_info "=========================================="
log_info ""

# 시스템 CA 확인
log_info "시스템 CA 신뢰 저장소:"
if [ "$OS_TYPE" = "rhel" ]; then
    if trust list | grep -q "harbor-ca" 2>/dev/null || \
       trust list | grep -q "Harbor CA" 2>/dev/null; then
        log_success "✓ Harbor CA가 시스템 신뢰 저장소에 등록됨"
    else
        log_warn "⚠ Harbor CA 확인 불가 (수동으로 확인 필요)"
    fi
else
    log_info "수동 확인: cat $CA_TRUST_DIR/harbor-ca.crt"
fi

# OpenSSL로 Harbor 연결 테스트
log_info ""
log_info "Harbor 연결 테스트:"
log_info "다음 명령으로 HTTPS 연결을 테스트할 수 있습니다:"
echo ""
echo "  # OpenSSL을 사용한 연결 테스트"
echo "  openssl s_client -connect ${HARBOR_HOSTNAME}:443 -CAfile $CA_CERT_FILE"
echo ""
echo "  # Docker 로그인 테스트"
echo "  docker login ${HARBOR_HOSTNAME}"
echo ""
echo "  # nerdctl 로그인 테스트"
echo "  nerdctl login ${HARBOR_HOSTNAME}"
echo ""

# 요약
log_info ""
log_info "=========================================="
log_success "Harbor CA 인증서 등록 완료!"
log_info "=========================================="
log_info ""
log_info "등록된 위치:"
log_info "  - 시스템 CA: $CA_TRUST_DIR/harbor-ca.crt"
if command -v docker &> /dev/null; then
    log_info "  - Docker: /etc/docker/certs.d/${HARBOR_HOSTNAME}/ca.crt"
fi
if command -v containerd &> /dev/null; then
    log_info "  - containerd: /etc/containerd/certs.d/${HARBOR_HOSTNAME}/ca.crt"
fi
if command -v nerdctl &> /dev/null; then
    log_info "  - nerdctl: containerd 설정 사용 (/etc/containerd/certs.d)"
fi
if command -v podman &> /dev/null; then
    log_info "  - Podman: /etc/containers/certs.d/${HARBOR_HOSTNAME}/ca.crt"
fi
log_info ""
log_info "이제 Harbor를 안전하게 사용할 수 있습니다!"
log_info ""

# 추가 안내
log_info "=========================================="
log_info "클라이언트 시스템 설정"
log_info "=========================================="
log_info ""
log_info "다른 클라이언트 시스템에서도 Harbor를 사용하려면:"
log_info "1. ca.crt 파일을 클라이언트 시스템으로 복사"
log_info "2. 다음 명령 실행:"
log_info ""
log_info "   sudo $0 ca.crt ${HARBOR_HOSTNAME}"
log_info ""
log_info "또는 수동 설치:"
log_info ""
log_info "   # RHEL/CentOS"
log_info "   sudo cp ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt"
log_info "   sudo update-ca-trust"
log_info ""
log_info "   # Ubuntu/Debian"
log_info "   sudo cp ca.crt /usr/local/share/ca-certificates/harbor-ca.crt"
log_info "   sudo update-ca-certificates"
log_info ""

# Kubernetes 환경을 위한 추가 안내
if command -v kubectl &> /dev/null; then
    log_info "=========================================="
    log_info "Kubernetes 환경 설정"
    log_info "=========================================="
    log_info ""
    log_info "K8s에서 Harbor 사용 시:"
    log_info ""
    log_info "1. imagePullSecret 생성:"
    log_info "   kubectl create secret docker-registry harbor-registry \\"
    log_info "     --docker-server=${HARBOR_HOSTNAME} \\"
    log_info "     --docker-username=admin \\"
    log_info "     --docker-password=<password> \\"
    log_info "     --namespace=default"
    log_info ""
    log_info "2. Pod에서 사용:"
    log_info "   apiVersion: v1"
    log_info "   kind: Pod"
    log_info "   spec:"
    log_info "     containers:"
    log_info "     - name: my-app"
    log_info "       image: ${HARBOR_HOSTNAME}/library/myimage:latest"
    log_info "     imagePullSecrets:"
    log_info "     - name: harbor-registry"
    log_info ""
fi

log_info "더 많은 정보는 README-KR.md를 참조하세요."
log_info ""

#!/bin/bash

################################################################################
# Harbor 설치 스크립트 (nerdctl/containerd 환경용)
# K8s가 설치되기 전에 이미지 registry로 사용
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

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한으로 실행해야 합니다."
    exit 1
fi

# .env 파일 로드
if [ -f .env ]; then
    log_info ".env 파일 로드 중..."
    set -a
    source .env
    set +a
else
    log_warn ".env 파일이 없습니다. 기본값을 사용합니다."
fi

# 기본 설정
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-192.168.1.100}"
HARBOR_HTTP_PORT="${HARBOR_HTTP_PORT:-80}"
HARBOR_HTTPS_PORT="${HARBOR_HTTPS_PORT:-443}"
HARBOR_DATA_VOLUME="${HARBOR_DATA_VOLUME:-/data}"
ENABLE_HTTPS="${ENABLE_HTTPS:-false}"

log_info ""
log_info "=========================================="
log_info "Harbor 설치 (nerdctl/containerd 환경)"
log_info "=========================================="
log_info ""

# 0. SELinux 및 방화벽 설정
log_info "Step 0/7: 시스템 설정 확인 중..."

# SELinux 비활성화
if [ "$DISABLE_SELINUX" = "true" ]; then
    if command -v getenforce &> /dev/null; then
        SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
        if [ "$SELINUX_STATUS" != "Disabled" ]; then
            log_warn "SELinux가 활성화되어 있습니다 ($SELINUX_STATUS). 비활성화 중..."
            setenforce 0 2>/dev/null || log_warn "SELinux를 Permissive로 설정할 수 없습니다."

            # /etc/selinux/config 파일 수정 (영구 비활성화)
            if [ -f /etc/selinux/config ]; then
                sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
                sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
                log_info "✓ SELinux 비활성화 완료 (재부팅 후 영구 적용)"
            fi
        else
            log_info "✓ SELinux가 이미 비활성화되어 있습니다"
        fi
    fi
else
    log_info "SELinux 설정 유지 (DISABLE_SELINUX=false)"
fi

# Firewalld 설정
if systemctl is-active --quiet firewalld; then
    if [ "$AUTO_CONFIGURE_FIREWALL" = "false" ]; then
        log_warn "firewalld가 실행 중입니다. 비활성화 중..."
        systemctl stop firewalld
        systemctl disable firewalld
        log_info "✓ firewalld 비활성화 완료"
    else
        log_info "firewalld 실행 중 (포트 자동 설정 예정)"
    fi
else
    log_info "✓ firewalld가 비활성화되어 있습니다"
fi

# 1. nerdctl 및 containerd 확인
log_info ""
log_info "Step 1/7: 컨테이너 런타임 확인 중..."

if ! command -v nerdctl &> /dev/null; then
    log_error "nerdctl이 설치되어 있지 않습니다."
    log_error "nerdctl을 먼저 설치하세요: https://github.com/containerd/nerdctl"
    exit 1
fi

if ! command -v containerd &> /dev/null; then
    log_error "containerd가 설치되어 있지 않습니다."
    exit 1
fi

log_info "nerdctl 버전: $(nerdctl --version | head -1)"
log_info "containerd 버전: $(containerd --version)"

# containerd 서비스 확인
if ! systemctl is-active --quiet containerd; then
    log_warn "containerd 서비스가 실행되지 않습니다. 시작합니다..."
    systemctl start containerd
    systemctl enable containerd
fi

log_info "containerd 서비스: 실행 중"

# Docker 명령 심볼릭 링크 생성 (Harbor prepare 스크립트용)
if ! command -v docker &> /dev/null; then
    log_info "docker 명령을 nerdctl로 심볼릭 링크 생성 중..."
    ln -sf $(which nerdctl) /usr/local/bin/docker
    log_info "✓ docker -> nerdctl 심볼릭 링크 생성 완료"
fi

# 2. nerdctl compose 확인 (nerdctl 전용 환경)
log_info ""
log_info "Step 2/7: Compose 도구 확인 중..."

# nerdctl 환경에서는 nerdctl compose만 사용
COMPOSE_CMD="nerdctl compose"
if ! nerdctl compose version &> /dev/null; then
    log_error "nerdctl compose를 사용할 수 없습니다."
    log_error "nerdctl 버전을 확인하세요: nerdctl --version"
    log_error "nerdctl compose는 nerdctl 1.0.0 이상에서 사용 가능합니다."
    exit 1
fi

log_info "nerdctl compose 사용: $(nerdctl compose version 2>&1 | head -1)"

# 3. Harbor 이미지 로드
log_info ""
log_info "Step 3/7: Harbor 이미지 로드 중..."

HARBOR_PACKAGE=$(ls harbor-offline-installer-*.tgz 2>/dev/null | head -1)
if [ -z "$HARBOR_PACKAGE" ]; then
    log_error "Harbor 설치 패키지를 찾을 수 없습니다."
    exit 1
fi

log_info "Harbor 패키지: $HARBOR_PACKAGE"

# 기존 Harbor 설치 확인
if [ -d "/opt/harbor" ]; then
    log_warn "/opt/harbor가 이미 존재합니다."

    # 실행 중인 Harbor 컨테이너 확인
    if cd /opt/harbor 2>/dev/null; then
        RUNNING_CONTAINERS=$(nerdctl compose ps -q 2>/dev/null | wc -l)
        if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
            log_warn "Harbor 컨테이너가 실행 중입니다 ($RUNNING_CONTAINERS개)."
            read -p "기존 Harbor를 중지하고 재설치하시겠습니까? (yes/no): " -r
            echo
            if [[ $REPLY =~ ^[Yy](es)?$ ]]; then
                log_info "기존 Harbor 중지 및 제거 중..."
                nerdctl compose down -v 2>/dev/null || true
                cd - > /dev/null
                rm -rf /opt/harbor
                log_info "✓ 기존 Harbor 제거 완료"
            else
                log_info "설치를 취소합니다."
                exit 0
            fi
        else
            cd - > /dev/null
        fi
    fi
fi

# Harbor 압축 해제
if [ ! -d "/opt/harbor" ]; then
    log_info "Harbor 압축 해제 중..."
    tar xzvf $HARBOR_PACKAGE -C /opt/
else
    log_warn "/opt/harbor가 이미 존재합니다. 기존 디렉토리 사용."
fi

cd /opt/harbor

# Harbor 이미지를 nerdctl로 로드
log_info "Harbor 이미지를 containerd로 로드 중..."

if [ -f "harbor.${HARBOR_VERSION#v}.tar.gz" ] || [ -f "harbor.*.tar.gz" ]; then
    IMAGE_TAR=$(ls harbor.*.tar.gz 2>/dev/null | head -1)
    if [ -n "$IMAGE_TAR" ]; then
        nerdctl load -i "$IMAGE_TAR"
        log_info "Harbor 이미지 로드 완료"
    fi
fi

# 4. Harbor 설정 파일 생성
log_info ""
log_info "Step 4/7: Harbor 설정 파일 생성 중..."

if [ ! -f "harbor.yml" ]; then
    cp harbor.yml.tmpl harbor.yml
    log_info "harbor.yml.tmpl에서 harbor.yml 복사 완료"

    # 설정 파일 자동 업데이트
    sed -i "s/^hostname:.*/hostname: ${HARBOR_HOSTNAME}/" harbor.yml

    if [ "$ENABLE_HTTPS" = "true" ]; then
        log_info "HTTPS 설정 활성화"

        # 인증서 파일 경로 결정
        CERT_SOURCE_DIR="${CERT_DIR:-./harbor-certs}"
        CERT_FILE="${CERT_SOURCE_DIR}/${HARBOR_HOSTNAME}.crt"
        KEY_FILE="${CERT_SOURCE_DIR}/${HARBOR_HOSTNAME}.key"

        # 인증서 파일 확인
        if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
            log_error "HTTPS 인증서를 찾을 수 없습니다:"
            log_error "  인증서: $CERT_FILE"
            log_error "  개인키: $KEY_FILE"
            log_error ""
            log_error "인증서를 먼저 생성하세요:"
            log_error "  ./generate-certs.sh"
            exit 1
        fi

        log_info "인증서 파일 확인 완료"
        log_info "  인증서: $CERT_FILE"
        log_info "  개인키: $KEY_FILE"

        # harbor.yml에 인증서 경로 설정
        sed -i "s|^#\?\s*certificate:.*|  certificate: $CERT_FILE|" harbor.yml
        sed -i "s|^#\?\s*private_key:.*|  private_key: $KEY_FILE|" harbor.yml
    else
        log_info "HTTP만 사용 (HTTPS 비활성화)"
        # HTTPS 섹션 주석 처리
        sed -i '/^https:/,/^[^ ]/ { /^https:/! { /^[^ ]/! s/^/#/ } }' harbor.yml
    fi

    log_info "Harbor 설정 업데이트 완료"
else
    log_warn "harbor.yml이 이미 존재합니다. 기존 설정 사용."
fi

# 5. 데이터 디렉토리 생성
log_info ""
log_info "Step 5/7: 데이터 디렉토리 생성 중..."

mkdir -p ${HARBOR_DATA_VOLUME}
log_info "데이터 디렉토리: ${HARBOR_DATA_VOLUME}"

# 6. Harbor 설치 및 시작
log_info ""
log_info "Step 6/7: Harbor 설치 중..."

# Harbor prepare 스크립트 실행하여 docker-compose.yml 생성
log_info "nerdctl compose용 설정 조정 중..."
./prepare

# Harbor 시작
log_info "Harbor 컨테이너 시작 중..."

# Docker 체크를 우회하고 직접 prepare와 compose 사용
log_info "Harbor 설정 준비 중..."
./prepare

log_info "Harbor 컨테이너 시작 (nerdctl compose 사용)..."
$COMPOSE_CMD up -d

# 7. 방화벽 설정 (firewalld가 실행 중이고 포트 설정이 필요한 경우)
log_info ""
log_info "Step 7/7: 방화벽 설정 중..."
if systemctl is-active --quiet firewalld && [ "$AUTO_CONFIGURE_FIREWALL" = "true" ]; then
    log_info "방화벽 규칙 추가 중..."
    firewall-cmd --permanent --add-port=${HARBOR_HTTP_PORT}/tcp
    if [ "$ENABLE_HTTPS" = "true" ]; then
        firewall-cmd --permanent --add-port=${HARBOR_HTTPS_PORT}/tcp
    fi
    firewall-cmd --reload
    log_info "✓ 방화벽 규칙 추가 완료"
else
    log_info "방화벽 설정 건너뜀 (firewalld 비활성화 또는 AUTO_CONFIGURE_FIREWALL=false)"
fi

# 8. systemd 서비스 생성
if [ "$CREATE_SYSTEMD_SERVICE" = "true" ]; then
    log_info "systemd 서비스 생성 중..."

    cat > /etc/systemd/system/harbor.service <<EOF
[Unit]
Description=Harbor Container Registry
Documentation=https://goharbor.io/docs/
After=network-online.target containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/harbor
ExecStart=/bin/bash -c '$COMPOSE_CMD up -d'
ExecStop=/bin/bash -c '$COMPOSE_CMD down'
ExecReload=/bin/bash -c '$COMPOSE_CMD restart'
Restart=on-failure
RestartSec=10s
TimeoutStartSec=0
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable harbor
    systemctl start harbor
    log_info "systemd 서비스 생성 및 시작 완료"
    log_info "  - 서비스 상태: systemctl status harbor"
    log_info "  - 서비스 시작: systemctl start harbor"
    log_info "  - 서비스 중지: systemctl stop harbor"
    log_info "  - 서비스 재시작: systemctl restart harbor"
fi

# 9. 설치 확인
log_info ""
log_info "설치 확인 중..."
sleep 5

$COMPOSE_CMD ps

log_info ""
log_info "=========================================="
log_info "${GREEN}Harbor 설치 완료!${NC}"
log_info "=========================================="
log_info ""
log_info "접속 정보:"
if [ "$ENABLE_HTTPS" = "true" ]; then
    log_info "  URL: https://${HARBOR_HOSTNAME}"
else
    log_info "  URL: http://${HARBOR_HOSTNAME}"
fi
log_info "  사용자명: admin"
log_info "  비밀번호: (harbor.yml에서 설정한 비밀번호)"
log_info ""
log_info "Harbor 관리 명령:"
log_info "  상태 확인: cd /opt/harbor && $COMPOSE_CMD ps"
log_info "  로그 확인: cd /opt/harbor && $COMPOSE_CMD logs -f"
log_info "  중지: cd /opt/harbor && $COMPOSE_CMD down"
log_info "  시작: cd /opt/harbor && $COMPOSE_CMD up -d"
log_info "  재시작: cd /opt/harbor && $COMPOSE_CMD restart"
log_info ""
log_info "nerdctl 사용 예제:"
log_info "  이미지 태그: nerdctl tag myimage:latest ${HARBOR_HOSTNAME}/library/myimage:latest"
log_info "  Harbor 로그인: nerdctl login ${HARBOR_HOSTNAME}"
log_info "  이미지 Push: nerdctl push ${HARBOR_HOSTNAME}/library/myimage:latest"
log_info ""

# HTTP 사용 시 insecure registry 설정 안내
if [ "$ENABLE_HTTPS" != "true" ]; then
    log_warn "=========================================="
    log_warn "HTTP를 사용하고 있습니다!"
    log_warn "=========================================="
    log_warn ""
    log_warn "nerdctl에서 insecure registry 설정:"
    log_warn ""
    log_warn "1. /etc/nerdctl/nerdctl.toml 파일 생성/편집:"
    log_warn "   mkdir -p /etc/nerdctl"
    log_warn "   vi /etc/nerdctl/nerdctl.toml"
    log_warn ""
    log_warn "2. 다음 내용 추가:"
    log_warn "   [registry.\"${HARBOR_HOSTNAME}\"]"
    log_warn "     insecure = true"
    log_warn ""
    log_warn "또는 containerd 설정:"
    log_warn ""
    log_warn "1. /etc/containerd/config.toml 편집"
    log_warn "2. [plugins.\"io.containerd.grpc.v1.cri\".registry.configs] 섹션에 추가:"
    log_warn "   [plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"${HARBOR_HOSTNAME}\".tls]"
    log_warn "     insecure_skip_verify = true"
    log_warn ""
    log_warn "3. containerd 재시작:"
    log_warn "   systemctl restart containerd"
    log_warn ""
fi

log_info "K8s 설치 시 Harbor를 private registry로 사용하려면:"
log_info "imagePullSecrets를 생성하세요:"
log_info ""
log_info "  kubectl create secret docker-registry harbor-registry \\"
log_info "    --docker-server=${HARBOR_HOSTNAME} \\"
log_info "    --docker-username=admin \\"
log_info "    --docker-password=<your-password>"
log_info ""

#!/bin/bash

################################################################################
# Harbor용 자체 서명 인증서 생성 스크립트
# HTTPS를 위한 사설 인증서를 생성합니다
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

# .env 파일 로드
if [ -f .env ]; then
    log_info ".env 파일 로드 중..."
    set -a
    source .env
    set +a
else
    log_warn ".env 파일이 없습니다. 기본값을 사용합니다."
fi

# 기본 설정 (.env 파일에서 설정하지 않은 경우 기본값 사용)
CERT_DIR="${CERT_DIR:-./harbor-certs}"
DAYS_VALID="${CERT_VALIDITY_DAYS:-3650}"
COUNTRY="${CERT_COUNTRY:-KR}"
STATE="${CERT_STATE:-Seoul}"
CITY="${CERT_CITY:-Seoul}"
ORG="${CERT_ORGANIZATION:-Harbor}"
OU="${CERT_ORGANIZATIONAL_UNIT:-IT}"

# 사용자 입력 받기
echo ""
echo -e "${BLUE}=========================================="
echo "Harbor 자체 서명 인증서 생성"
echo -e "==========================================${NC}"
echo ""

# .env에서 호스트명이 설정된 경우 기본값으로 사용
DEFAULT_HOSTNAME="${HARBOR_HOSTNAME:-192.168.1.100}"

# 호스트명 입력
read -p "Harbor 서버 호스트명 또는 IP 주소 입력 [$DEFAULT_HOSTNAME]: " HOSTNAME
HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"

if [ -z "$HOSTNAME" ]; then
    log_error "호스트명은 필수 입력 사항입니다."
    exit 1
fi

# 추가 SAN (Subject Alternative Name) 입력
echo ""
if [ -n "$CERT_ADDITIONAL_SANS" ]; then
    log_info "추가 SAN (.env에서 로드): $CERT_ADDITIONAL_SANS"
    log_info "다른 값을 입력하려면 입력하세요 (엔터키로 .env 값 사용)"
else
    log_info "추가 도메인이나 IP를 입력하세요 (선택사항, 쉼표로 구분)"
    log_info "예: harbor.example.com,192.168.1.100,10.0.0.1"
fi
read -p "추가 SAN (엔터키로 건너뛰기): " INPUT_SANS
ADDITIONAL_SANS="${INPUT_SANS:-$CERT_ADDITIONAL_SANS}"

# 인증서 디렉토리 생성
log_info "인증서 디렉토리 생성: $CERT_DIR"
mkdir -p $CERT_DIR
cd $CERT_DIR

# OpenSSL 설치 확인
if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL이 설치되어 있지 않습니다."
    log_error "설치: yum install -y openssl"
    exit 1
fi

# CA (Certificate Authority) 생성
log_info "Step 1/4: CA 개인키 생성 중..."
openssl genrsa -out ca.key 4096

log_info "Step 2/4: CA 인증서 생성 중..."
openssl req -x509 -new -nodes -sha512 -days $DAYS_VALID \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/OU=${OU}/CN=Harbor CA" \
    -key ca.key \
    -out ca.crt

# 서버 인증서 생성
log_info "Step 3/4: 서버 개인키 생성 중..."
openssl genrsa -out ${HOSTNAME}.key 4096

log_info "Step 4/4: 서버 인증서 생성 중..."

# CSR (Certificate Signing Request) 생성
openssl req -sha512 -new \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/OU=${OU}/CN=${HOSTNAME}" \
    -key ${HOSTNAME}.key \
    -out ${HOSTNAME}.csr

# x509 v3 확장 파일 생성
cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=${HOSTNAME}
EOF

# 추가 SAN 처리
SAN_INDEX=2
IP_INDEX=1

# 호스트명이 IP인지 확인
if [[ $HOSTNAME =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "IP.${IP_INDEX}=${HOSTNAME}" >> v3.ext
    IP_INDEX=$((IP_INDEX + 1))
fi

# 추가 SAN 처리
if [ ! -z "$ADDITIONAL_SANS" ]; then
    IFS=',' read -ra SANS <<< "$ADDITIONAL_SANS"
    for san in "${SANS[@]}"; do
        san=$(echo $san | xargs)  # 공백 제거
        if [[ $san =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # IP 주소
            echo "IP.${IP_INDEX}=${san}" >> v3.ext
            IP_INDEX=$((IP_INDEX + 1))
        else
            # 도메인 이름
            echo "DNS.${SAN_INDEX}=${san}" >> v3.ext
            SAN_INDEX=$((SAN_INDEX + 1))
        fi
    done
fi

# 서버 인증서 서명
openssl x509 -req -sha512 -days $DAYS_VALID \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in ${HOSTNAME}.csr \
    -out ${HOSTNAME}.crt

# Docker용 인증서 포맷 생성
log_info "Docker용 인증서 포맷 변환 중..."
openssl x509 -inform PEM -in ${HOSTNAME}.crt -out ${HOSTNAME}.cert

# 설치 스크립트 생성
cat > install-certs.sh <<'INSTALL_CERTS_EOF'
#!/bin/bash

################################################################################
# Harbor 인증서 설치 스크립트
################################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한으로 실행해야 합니다."
    exit 1
fi

HOSTNAME_FILE=$(ls *.crt 2>/dev/null | grep -v ca.crt | head -1)
HOSTNAME=${HOSTNAME_FILE%.crt}

if [ -z "$HOSTNAME" ]; then
    log_error "인증서 파일을 찾을 수 없습니다."
    exit 1
fi

log_info "인증서 설치 시작..."
log_info "호스트명: $HOSTNAME"

# Harbor 인증서 디렉토리 생성
HARBOR_CERT_DIR="/etc/harbor/ssl"
mkdir -p $HARBOR_CERT_DIR

# 인증서 복사
log_info "Harbor 인증서 복사 중..."
cp ${HOSTNAME}.crt $HARBOR_CERT_DIR/
cp ${HOSTNAME}.key $HARBOR_CERT_DIR/
cp ca.crt $HARBOR_CERT_DIR/

# 권한 설정
chmod 644 $HARBOR_CERT_DIR/${HOSTNAME}.crt
chmod 600 $HARBOR_CERT_DIR/${HOSTNAME}.key
chmod 644 $HARBOR_CERT_DIR/ca.crt

# Docker 인증서 디렉토리 생성
DOCKER_CERT_DIR="/etc/docker/certs.d/${HOSTNAME}"
mkdir -p $DOCKER_CERT_DIR

log_info "Docker 인증서 복사 중..."
cp ${HOSTNAME}.cert $DOCKER_CERT_DIR/
cp ${HOSTNAME}.key $DOCKER_CERT_DIR/
cp ca.crt $DOCKER_CERT_DIR/

# 시스템 신뢰 인증서에 CA 추가
log_info "시스템 신뢰 인증서에 CA 추가 중..."
cp ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt
update-ca-trust

log_info ""
log_info "=========================================="
log_info "인증서 설치 완료!"
log_info "=========================================="
log_info ""
log_info "인증서 파일 위치:"
log_info "  Harbor: $HARBOR_CERT_DIR/"
log_info "  Docker: $DOCKER_CERT_DIR/"
log_info "  CA: /etc/pki/ca-trust/source/anchors/harbor-ca.crt"
log_info ""
log_info "다음 단계:"
log_info "1. Harbor 설정 파일 편집: vi /opt/harbor/harbor.yml"
log_info "2. HTTPS 섹션 활성화 및 경로 설정:"
log_info "   https:"
log_info "     port: 443"
log_info "     certificate: $HARBOR_CERT_DIR/${HOSTNAME}.crt"
log_info "     private_key: $HARBOR_CERT_DIR/${HOSTNAME}.key"
log_info "3. Harbor 재설치: cd /opt/harbor && ./install.sh"
log_info ""

INSTALL_CERTS_EOF

chmod +x install-certs.sh

# 인증서 정보 표시
log_info ""
log_info "=========================================="
log_info "${GREEN}인증서 생성 완료!${NC}"
log_info "=========================================="
log_info ""
log_info "생성된 파일:"
log_info "  CA 인증서: ca.crt"
log_info "  CA 개인키: ca.key"
log_info "  서버 인증서: ${HOSTNAME}.crt"
log_info "  서버 개인키: ${HOSTNAME}.key"
log_info "  Docker용 인증서: ${HOSTNAME}.cert"
log_info "  인증서 요청: ${HOSTNAME}.csr"
log_info "  설치 스크립트: install-certs.sh"
log_info ""

# 인증서 정보 확인
log_info "인증서 정보:"
log_info "=========================================="
openssl x509 -in ${HOSTNAME}.crt -noout -text | grep -A2 "Subject:"
openssl x509 -in ${HOSTNAME}.crt -noout -text | grep -A10 "Subject Alternative Name"
echo ""
openssl x509 -in ${HOSTNAME}.crt -noout -dates
log_info "=========================================="
echo ""

log_info "다음 단계:"
log_info "1. 오프라인 시스템에서 인증서 설치:"
log_info "   sudo ./install-certs.sh"
log_info ""
log_info "2. 클라이언트 시스템에 CA 인증서 설치:"
log_info "   # RHEL/CentOS:"
log_info "   sudo cp ca.crt /etc/pki/ca-trust/source/anchors/harbor-ca.crt"
log_info "   sudo update-ca-trust"
log_info ""
log_info "   # Ubuntu/Debian:"
log_info "   sudo cp ca.crt /usr/local/share/ca-certificates/harbor-ca.crt"
log_info "   sudo update-ca-certificates"
log_info ""
log_info "3. Harbor 설정 파일에서 HTTPS 활성화"
log_info ""

# 인증서 패키징
cd ..
CERT_PACKAGE="harbor-certs-${HOSTNAME}.tar.gz"
tar -czf $CERT_PACKAGE harbor-certs/

log_info "인증서 패키지 생성: $CERT_PACKAGE"
log_info "크기: $(du -sh $CERT_PACKAGE | awk '{print $1}')"
log_info ""
log_info "이 패키지를 오프라인 시스템으로 전송하세요."
log_info ""

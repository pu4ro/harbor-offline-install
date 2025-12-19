#!/bin/bash

################################################################################
# Harbor 이미지 export 스크립트
# 설치된 Harbor 이미지를 tar 파일로 export하여 오프라인 전송 준비
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
fi

HARBOR_VERSION="${HARBOR_VERSION:-v2.11.1}"
PACKAGE_DIR="${PACKAGE_DIR:-harbor-offline-packages}"
IMAGE_EXPORT_DIR="${PACKAGE_DIR}/harbor-images"

log_info "Harbor 이미지 export 시작..."
log_info "Harbor 버전: $HARBOR_VERSION"

# 이미지 export 디렉토리 생성
mkdir -p "$IMAGE_EXPORT_DIR"

# Harbor 이미지 목록
HARBOR_IMAGES=(
    "goharbor/harbor-core:${HARBOR_VERSION}"
    "goharbor/harbor-portal:${HARBOR_VERSION}"
    "goharbor/harbor-jobservice:${HARBOR_VERSION}"
    "goharbor/harbor-log:${HARBOR_VERSION}"
    "goharbor/harbor-db:${HARBOR_VERSION}"
    "goharbor/registry-photon:${HARBOR_VERSION}"
    "goharbor/harbor-registryctl:${HARBOR_VERSION}"
    "goharbor/redis-photon:${HARBOR_VERSION}"
    "goharbor/nginx-photon:${HARBOR_VERSION}"
)

# nerdctl 확인
if ! command -v nerdctl &> /dev/null; then
    log_error "nerdctl이 설치되어 있지 않습니다."
    exit 1
fi

log_info "이미지 export 중..."

for image in "${HARBOR_IMAGES[@]}"; do
    image_name=$(echo "$image" | tr '/:' '_')
    tar_file="${IMAGE_EXPORT_DIR}/${image_name}.tar"

    log_info "  - $image"

    # 이미지가 로컬에 있는지 확인
    if nerdctl images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"; then
        nerdctl save -o "$tar_file" "$image"
        log_info "    ✓ Exported: $tar_file"
    else
        log_warn "    ✗ 이미지를 찾을 수 없습니다: $image"
        log_warn "    Harbor가 설치되어 있지 않거나 이미지가 로드되지 않았습니다."
    fi
done

# Trivy, Notary, ChartMuseum 이미지 (설치된 경우)
OPTIONAL_IMAGES=(
    "goharbor/trivy-adapter-photon:${HARBOR_VERSION}"
    "goharbor/notary-server-photon:${HARBOR_VERSION}"
    "goharbor/notary-signer-photon:${HARBOR_VERSION}"
    "goharbor/chartmuseum-photon:${HARBOR_VERSION}"
)

log_info "선택적 이미지 확인 중..."
for image in "${OPTIONAL_IMAGES[@]}"; do
    if nerdctl images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"; then
        image_name=$(echo "$image" | tr '/:' '_')
        tar_file="${IMAGE_EXPORT_DIR}/${image_name}.tar"
        log_info "  - $image"
        nerdctl save -o "$tar_file" "$image"
        log_info "    ✓ Exported: $tar_file"
    fi
done

# 이미지 목록 파일 생성
log_info "이미지 목록 파일 생성 중..."
cat > "${IMAGE_EXPORT_DIR}/image-list.txt" << EOF
# Harbor Images (${HARBOR_VERSION})
# Exported on: $(date)

EOF

for image in "${HARBOR_IMAGES[@]}"; do
    echo "$image" >> "${IMAGE_EXPORT_DIR}/image-list.txt"
done

# 이미지 import 스크립트 생성
log_info "이미지 import 스크립트 생성 중..."
cat > "${IMAGE_EXPORT_DIR}/import-images.sh" << 'IMPORT_SCRIPT'
#!/bin/bash

set -e

GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

if ! command -v nerdctl &> /dev/null; then
    echo "[ERROR] nerdctl이 설치되어 있지 않습니다."
    exit 1
fi

log_info "Harbor 이미지 import 중..."

for tar_file in *.tar; do
    if [ -f "$tar_file" ]; then
        log_info "  - $tar_file"
        nerdctl load -i "$tar_file"
    fi
done

log_info "이미지 import 완료!"
log_info "이미지 목록 확인: nerdctl images | grep goharbor"
IMPORT_SCRIPT

chmod +x "${IMAGE_EXPORT_DIR}/import-images.sh"

# 요약
log_info ""
log_info "=========================================="
log_info "Harbor 이미지 export 완료!"
log_info "=========================================="
log_info "Export 디렉토리: $IMAGE_EXPORT_DIR"
log_info "이미지 개수: $(ls -1 ${IMAGE_EXPORT_DIR}/*.tar 2>/dev/null | wc -l)"
log_info "총 크기: $(du -sh $IMAGE_EXPORT_DIR | cut -f1)"
log_info ""
log_info "오프라인 시스템에서 import 방법:"
log_info "  cd $IMAGE_EXPORT_DIR"
log_info "  ./import-images.sh"
log_info ""

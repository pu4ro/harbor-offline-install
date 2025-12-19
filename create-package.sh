#!/bin/bash

################################################################################
# Harbor 오프라인 설치 패키지 생성 스크립트
# 다운로드한 모든 파일을 하나의 tar.gz 파일로 압축합니다
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

# 패키지 디렉토리 확인
PACKAGE_DIR="harbor-offline-packages"

if [ ! -d "$PACKAGE_DIR" ]; then
    log_error "패키지 디렉토리가 존재하지 않습니다: $PACKAGE_DIR"
    log_error "먼저 download-packages.sh를 실행하세요."
    exit 1
fi

# 패키지 파일명 생성 (날짜 포함)
DATE=$(date +%Y%m%d)
PACKAGE_NAME="harbor-offline-rhel96-${DATE}.tar.gz"

log_info "패키지 생성 시작..."
log_info "패키지명: $PACKAGE_NAME"
log_info ""

# 패키지 내용 확인
log_info "패키지에 포함될 파일 목록:"
log_info "=========================================="
du -sh $PACKAGE_DIR
echo ""
find $PACKAGE_DIR -type f -exec ls -lh {} \; | awk '{print "  " $9 " (" $5 ")"}'
log_info "=========================================="
echo ""

# 압축 시작
log_info "압축 중... (용량이 크므로 시간이 걸릴 수 있습니다)"
tar -czf $PACKAGE_NAME $PACKAGE_DIR

if [ $? -eq 0 ]; then
    log_info ""
    log_info "=========================================="
    log_info "${GREEN}패키지 생성 완료!${NC}"
    log_info "=========================================="
    log_info ""
    log_info "패키지 정보:"
    log_info "  파일명: $PACKAGE_NAME"
    log_info "  크기: $(du -sh $PACKAGE_NAME | awk '{print $1}')"
    log_info "  위치: $(pwd)/$PACKAGE_NAME"
    log_info ""
    log_info "MD5 체크섬:"
    md5sum $PACKAGE_NAME | tee ${PACKAGE_NAME}.md5
    log_info ""
    log_info "SHA256 체크섬:"
    sha256sum $PACKAGE_NAME | tee ${PACKAGE_NAME}.sha256
    log_info ""
    log_info "=========================================="
    log_info "오프라인 시스템으로 전송 방법:"
    log_info "=========================================="
    log_info ""
    log_info "1. USB 드라이브 사용:"
    log_info "   cp $PACKAGE_NAME /path/to/usb/"
    log_info ""
    log_info "2. SCP 사용 (네트워크로 전송 가능한 경우):"
    log_info "   scp $PACKAGE_NAME user@offline-server:/root/"
    log_info ""
    log_info "3. 오프라인 시스템에서 압축 해제:"
    log_info "   tar -xzf $PACKAGE_NAME"
    log_info "   cd $PACKAGE_DIR"
    log_info "   sudo ./install-offline.sh"
    log_info ""
    log_info "자세한 설치 방법은 INSTALL-GUIDE-KR.txt를 참조하세요."
    log_info ""

    # 압축 해제 스크립트 생성
    cat > extract-and-install.sh << 'EXTRACT_EOF'
#!/bin/bash

################################################################################
# Harbor 오프라인 패키지 압축 해제 및 설치 가이드 스크립트
################################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "Harbor 오프라인 설치 패키지 압축 해제"
echo -e "==========================================${NC}"
echo ""

# tar.gz 파일 찾기
PACKAGE_FILE=$(ls harbor-offline-rhel96-*.tar.gz 2>/dev/null | head -1)

if [ -z "$PACKAGE_FILE" ]; then
    echo -e "${YELLOW}[경고]${NC} harbor-offline-rhel96-*.tar.gz 파일을 찾을 수 없습니다."
    echo ""
    echo "사용법:"
    echo "  1. 이 스크립트와 같은 디렉토리에 패키지 파일을 위치시키세요"
    echo "  2. 또는 직접 압축 해제: tar -xzf harbor-offline-rhel96-YYYYMMDD.tar.gz"
    exit 1
fi

echo "발견된 패키지: $PACKAGE_FILE"
echo ""

# 체크섬 검증 (있는 경우)
if [ -f "${PACKAGE_FILE}.md5" ]; then
    echo "MD5 체크섬 검증 중..."
    md5sum -c ${PACKAGE_FILE}.md5
    echo ""
fi

if [ -f "${PACKAGE_FILE}.sha256" ]; then
    echo "SHA256 체크섬 검증 중..."
    sha256sum -c ${PACKAGE_FILE}.sha256
    echo ""
fi

# 압축 해제
echo "압축 해제 중..."
tar -xzf $PACKAGE_FILE

echo ""
echo -e "${GREEN}압축 해제 완료!${NC}"
echo ""
echo "다음 단계:"
echo "  cd harbor-offline-packages"
echo "  sudo ./install-offline.sh"
echo ""
echo "자세한 내용은 INSTALL-GUIDE-KR.txt를 참조하세요."

EXTRACT_EOF

    chmod +x extract-and-install.sh

    log_info "추가로 생성된 파일:"
    log_info "  - extract-and-install.sh (압축 해제 스크립트)"
    log_info "  - ${PACKAGE_NAME}.md5 (체크섬 파일)"
    log_info "  - ${PACKAGE_NAME}.sha256 (체크섬 파일)"
    log_info ""

else
    log_error "패키지 생성 실패"
    exit 1
fi

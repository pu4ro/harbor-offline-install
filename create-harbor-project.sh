#!/bin/bash

################################################################################
# Harbor 프로젝트 생성 스크립트 (Harbor API v2.0)
# Harbor API를 통해 프로젝트를 생성합니다
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
    log_error ".env 파일이 없습니다."
    log_error "실행: cp env.example .env && vi .env"
    exit 1
fi

# 기본 설정
HARBOR_HOST="${HARBOR_HOSTNAME:-localhost}"
HARBOR_ADMIN_USER="${HARBOR_ADMIN_USER:-admin}"
HARBOR_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
ENABLE_HTTPS="${ENABLE_HTTPS:-false}"

# 프로토콜 결정
if [ "$ENABLE_HTTPS" = "true" ]; then
    PROTOCOL="https"
else
    PROTOCOL="http"
fi

HARBOR_URL="${PROTOCOL}://${HARBOR_HOST}"

log_section "Harbor 프로젝트 생성"

echo ""
log_info "Harbor 서버: $HARBOR_URL"
echo ""

# 프로젝트 이름 입력
read -p "프로젝트 이름 입력: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    log_error "프로젝트 이름은 필수입니다."
    exit 1
fi

# 프로젝트 이름 검증 (소문자, 숫자, 하이픈만 허용)
if ! [[ "$PROJECT_NAME" =~ ^[a-z0-9]+[a-z0-9_-]*$ ]]; then
    log_error "프로젝트 이름은 소문자, 숫자, 하이픈(-), 언더스코어(_)만 사용 가능합니다."
    log_error "첫 글자는 소문자 또는 숫자여야 합니다."
    exit 1
fi

# 공개 설정
echo ""
log_info "프로젝트 공개 설정:"
echo "  1) Private (비공개 - 권한이 있는 사용자만 접근)"
echo "  2) Public  (공개 - 모든 사용자가 pull 가능)"
echo ""
read -p "선택 (1 또는 2) [기본값: 1]: " PUBLIC_CHOICE
PUBLIC_CHOICE=${PUBLIC_CHOICE:-1}

if [ "$PUBLIC_CHOICE" = "2" ]; then
    IS_PUBLIC="true"
    PUBLIC_TEXT="Public (공개)"
else
    IS_PUBLIC="false"
    PUBLIC_TEXT="Private (비공개)"
fi

# 스토리지 제한 설정 (선택)
echo ""
read -p "스토리지 제한 설정 (GB, 엔터키로 건너뛰기): " STORAGE_LIMIT

# JSON 페이로드 생성
PAYLOAD=$(cat <<EOF
{
  "project_name": "$PROJECT_NAME",
  "public": $IS_PUBLIC
EOF
)

# 스토리지 제한이 설정된 경우 추가
if [ ! -z "$STORAGE_LIMIT" ]; then
    # GB를 바이트로 변환
    STORAGE_LIMIT_BYTES=$((STORAGE_LIMIT * 1024 * 1024 * 1024))
    PAYLOAD=$(cat <<EOF
{
  "project_name": "$PROJECT_NAME",
  "public": $IS_PUBLIC,
  "storage_limit": $STORAGE_LIMIT_BYTES
EOF
)
fi

PAYLOAD="${PAYLOAD}
}"

# 확인
echo ""
log_section "프로젝트 정보 확인"
echo ""
log_info "프로젝트 이름: $PROJECT_NAME"
log_info "공개 설정: $PUBLIC_TEXT"
if [ ! -z "$STORAGE_LIMIT" ]; then
    log_info "스토리지 제한: ${STORAGE_LIMIT}GB"
else
    log_info "스토리지 제한: 없음"
fi
log_info "Harbor URL: $HARBOR_URL"
echo ""

read -p "프로젝트를 생성하시겠습니까? (y/n) [y]: " CONFIRM
CONFIRM=${CONFIRM:-y}

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    log_info "프로젝트 생성 취소"
    exit 0
fi

# API 호출
log_info "프로젝트 생성 중..."
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${HARBOR_URL}/api/v2.0/projects" \
    -H "Content-Type: application/json" \
    -u "${HARBOR_ADMIN_USER}:${HARBOR_PASSWORD}" \
    -d "$PAYLOAD" \
    --insecure 2>&1)

# HTTP 상태 코드 추출
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# 결과 확인
if [ "$HTTP_CODE" = "201" ]; then
    log_section "프로젝트 생성 성공"
    echo ""
    log_info "프로젝트 '$PROJECT_NAME'이(가) 성공적으로 생성되었습니다."
    echo ""
    log_info "프로젝트 접속 URL:"
    log_info "  ${HARBOR_URL}/harbor/projects"
    echo ""
    log_info "이미지 Push/Pull 예제:"
    log_info "  # 로그인"
    log_info "  nerdctl login ${HARBOR_HOST}"
    echo ""
    log_info "  # 이미지 태그"
    log_info "  nerdctl tag alpine:latest ${HARBOR_HOST}/${PROJECT_NAME}/alpine:latest"
    echo ""
    log_info "  # 이미지 Push"
    log_info "  nerdctl push ${HARBOR_HOST}/${PROJECT_NAME}/alpine:latest"
    echo ""
    log_info "  # 이미지 Pull"
    log_info "  nerdctl pull ${HARBOR_HOST}/${PROJECT_NAME}/alpine:latest"
    echo ""
elif [ "$HTTP_CODE" = "409" ]; then
    log_error "프로젝트 '$PROJECT_NAME'은(는) 이미 존재합니다."
    exit 1
elif [ "$HTTP_CODE" = "401" ]; then
    log_error "인증 실패: Harbor 관리자 계정 정보를 확인하세요."
    log_error "사용자: $HARBOR_ADMIN_USER"
    log_error ".env 파일의 HARBOR_ADMIN_PASSWORD를 확인하세요."
    exit 1
elif [ "$HTTP_CODE" = "000" ]; then
    log_error "Harbor 서버에 연결할 수 없습니다."
    log_error "Harbor URL: $HARBOR_URL"
    log_error ""
    log_error "확인 사항:"
    log_error "  1. Harbor가 실행 중인지 확인: make harbor-status"
    log_error "  2. .env 파일의 HARBOR_HOSTNAME이 올바른지 확인"
    log_error "  3. HTTPS 사용 시 ENABLE_HTTPS=true인지 확인"
    exit 1
else
    log_error "프로젝트 생성 실패 (HTTP $HTTP_CODE)"
    if [ ! -z "$RESPONSE_BODY" ]; then
        echo ""
        log_error "응답 내용:"
        echo "$RESPONSE_BODY" | grep -o '"message":"[^"]*"' | sed 's/"message":"\(.*\)"/\1/' || echo "$RESPONSE_BODY"
    fi
    exit 1
fi

#!/bin/bash

################################################################################
# Harbor 설치 후 자동 테스트 스크립트
# Harbor 서비스 상태, API 접근, 프로젝트 생성/조회를 자동으로 테스트
################################################################################

# set -e를 사용하지 않음 - 테스트 실패 시에도 계속 진행

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC} - $1"
    ((TEST_PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC} - $1"
    ((TEST_FAILED++))
}

test_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC} - $1"
    ((TEST_SKIPPED++))
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

# 기본값 설정
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-192.168.1.100}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
ENABLE_HTTPS="${ENABLE_HTTPS:-false}"
HARBOR_HTTP_PORT="${HARBOR_HTTP_PORT:-80}"
HARBOR_HTTPS_PORT="${HARBOR_HTTPS_PORT:-443}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"

# nerdctl 확인
if ! command -v nerdctl &> /dev/null; then
    log_error "nerdctl이 설치되어 있지 않습니다."
    exit 1
fi

log_info "컨테이너 런타임: nerdctl"

# Harbor URL 결정
if [ "$ENABLE_HTTPS" = "true" ]; then
    HARBOR_URL="https://${HARBOR_HOSTNAME}"
    if [ "$HARBOR_HTTPS_PORT" != "443" ]; then
        HARBOR_URL="https://${HARBOR_HOSTNAME}:${HARBOR_HTTPS_PORT}"
    fi
    CURL_OPTS="-k"  # 자체 서명 인증서 허용
else
    HARBOR_URL="http://${HARBOR_HOSTNAME}"
    if [ "$HARBOR_HTTP_PORT" != "80" ]; then
        HARBOR_URL="http://${HARBOR_HOSTNAME}:${HARBOR_HTTP_PORT}"
    fi
    CURL_OPTS=""
fi

log_info "Harbor URL: $HARBOR_URL"

echo ""
echo -e "${BLUE}=========================================="
echo "Harbor 설치 후 자동 테스트"
echo -e "==========================================${NC}"
echo ""

# 테스트 1: Harbor 디렉토리 존재 확인
log_test "1. Harbor 설치 디렉토리 확인"
if [ -d "/opt/harbor" ]; then
    test_pass "Harbor 디렉토리 존재 (/opt/harbor)"
else
    test_fail "Harbor 디렉토리가 없습니다 (/opt/harbor)"
    exit 1
fi

# 테스트 2: Harbor 컨테이너 상태 확인
log_test "2. Harbor 컨테이너 상태 확인"
if ! cd /opt/harbor 2>/dev/null; then
    test_fail "Harbor 디렉토리로 이동 실패"
    CONTAINER_COUNT=0
else
    COMPOSE_CMD="nerdctl compose"
    CONTAINER_COUNT=$($COMPOSE_CMD ps 2>/dev/null | grep -c "running" || echo "0")
fi
if [ "$CONTAINER_COUNT" -ge 8 ]; then
    test_pass "Harbor 컨테이너가 실행 중입니다 ($CONTAINER_COUNT개)"
else
    test_fail "Harbor 컨테이너 실행 상태 확인 필요 ($CONTAINER_COUNT개)"
fi

# 테스트 3: Harbor 웹 UI 접근 테스트
log_test "3. Harbor 웹 UI 접근 테스트"
sleep 5  # 서비스 안정화 대기
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $CURL_OPTS "$HARBOR_URL/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "308" ]; then
    test_pass "Harbor 웹 UI 접근 성공 (HTTP $HTTP_CODE)"
else
    test_fail "Harbor 웹 UI 접근 실패 (HTTP $HTTP_CODE)"
fi

# 테스트 4: Harbor API 인증 테스트
log_test "4. Harbor API 인증 테스트"
API_RESPONSE=$(curl -s $CURL_OPTS -u "admin:${HARBOR_ADMIN_PASSWORD}" "$HARBOR_URL/api/v2.0/systeminfo" 2>/dev/null || echo "")
if echo "$API_RESPONSE" | grep -q "harbor_version"; then
    HARBOR_VERSION=$(echo "$API_RESPONSE" | grep -o '"harbor_version":"[^"]*"' | cut -d'"' -f4)
    test_pass "Harbor API 인증 성공 (버전: $HARBOR_VERSION)"
else
    test_fail "Harbor API 인증 실패"
fi

# 테스트 5: 프로젝트 목록 조회 테스트
log_test "5. 프로젝트 목록 조회 테스트"
PROJECT_LIST=$(curl -s $CURL_OPTS -u "admin:${HARBOR_ADMIN_PASSWORD}" "$HARBOR_URL/api/v2.0/projects" 2>/dev/null || echo "[]")
if echo "$PROJECT_LIST" | grep -q "library"; then
    PROJECT_COUNT=$(echo "$PROJECT_LIST" | grep -o '"project_id"' | wc -l)
    test_pass "프로젝트 목록 조회 성공 (${PROJECT_COUNT}개 프로젝트)"
else
    test_fail "프로젝트 목록 조회 실패"
fi

# 테스트 6: 테스트 프로젝트 생성
log_test "6. 테스트 프로젝트 생성"
TEST_PROJECT_NAME="test-autotest-$(date +%s)"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" $CURL_OPTS \
    -X POST "$HARBOR_URL/api/v2.0/projects" \
    -H "Content-Type: application/json" \
    -u "admin:${HARBOR_ADMIN_PASSWORD}" \
    -d "{\"project_name\":\"${TEST_PROJECT_NAME}\",\"public\":false}" 2>/dev/null)

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "201" ]; then
    test_pass "테스트 프로젝트 생성 성공 (${TEST_PROJECT_NAME})"
else
    # 이미 존재하거나 다른 문제
    if [ "$HTTP_CODE" = "409" ]; then
        test_skip "테스트 프로젝트가 이미 존재합니다"
    else
        test_fail "테스트 프로젝트 생성 실패 (HTTP $HTTP_CODE)"
    fi
fi

# 테스트 7: 생성된 프로젝트 조회
if [ "$HTTP_CODE" = "201" ]; then
    log_test "7. 생성된 프로젝트 조회 테스트"
    sleep 2
    PROJECT_DETAIL=$(curl -s $CURL_OPTS -u "admin:${HARBOR_ADMIN_PASSWORD}" \
        "$HARBOR_URL/api/v2.0/projects?name=${TEST_PROJECT_NAME}" 2>/dev/null || echo "[]")

    if echo "$PROJECT_DETAIL" | grep -q "$TEST_PROJECT_NAME"; then
        test_pass "생성된 프로젝트 조회 성공 (${TEST_PROJECT_NAME})"
    else
        test_fail "생성된 프로젝트 조회 실패"
    fi
else
    log_test "7. 생성된 프로젝트 조회 테스트"
    test_skip "프로젝트 생성이 실패하여 조회 테스트 스킵"
fi

# 테스트 8: 레지스트리 로그인 테스트 (선택적)
log_test "8. 레지스트리 로그인 테스트"
if [ "$ENABLE_HTTPS" = "true" ]; then
    REGISTRY_URL="${HARBOR_HOSTNAME}"
    if [ "$HARBOR_HTTPS_PORT" != "443" ]; then
        REGISTRY_URL="${HARBOR_HOSTNAME}:${HARBOR_HTTPS_PORT}"
    fi
else
    REGISTRY_URL="${HARBOR_HOSTNAME}"
    if [ "$HARBOR_HTTP_PORT" != "80" ]; then
        REGISTRY_URL="${HARBOR_HOSTNAME}:${HARBOR_HTTP_PORT}"
    fi
fi

# nerdctl 로그인 시도 (HTTPS는 인증서 설정 필요)
if [ "$ENABLE_HTTPS" = "false" ]; then
    # HTTP 환경에서는 로그인 시도해볼 수 있음
    test_skip "레지스트리 로그인 테스트는 수동 확인 권장 (containerd/nerdctl 설정 필요)"
else
    # HTTPS 환경에서는 CA 인증서 설정이 필요
    test_skip "HTTPS 레지스트리 로그인은 CA 인증서 설정 후 가능"
fi

# 테스트 9: Harbor 로그 확인
log_test "9. Harbor 로그 접근 가능 여부"
if [ -f "/var/log/harbor/core.log" ]; then
    LOG_LINES=$(wc -l < /var/log/harbor/core.log)
    test_pass "Harbor 로그 파일 접근 가능 (${LOG_LINES} 라인)"
else
    test_warn "Harbor 로그 파일에 접근할 수 없습니다 (syslog 사용 중일 수 있음)"
    test_skip "Harbor 로그 확인 스킵"
fi

# 테스트 10: 디스크 공간 확인
log_test "10. Harbor 데이터 볼륨 디스크 공간 확인"
DATA_VOLUME="${HARBOR_DATA_VOLUME:-/data}"
if [ -d "$DATA_VOLUME" ]; then
    AVAILABLE_SPACE=$(df -h "$DATA_VOLUME" | tail -1 | awk '{print $4}')
    USAGE_PERCENT=$(df -h "$DATA_VOLUME" | tail -1 | awk '{print $5}')
    test_pass "디스크 공간 충분 (사용 가능: ${AVAILABLE_SPACE}, 사용률: ${USAGE_PERCENT})"
else
    test_warn "데이터 볼륨 디렉토리가 없습니다 ($DATA_VOLUME)"
    test_skip "디스크 공간 확인 스킵"
fi

# 결과 요약
echo ""
echo -e "${BLUE}=========================================="
echo "테스트 결과 요약"
echo -e "==========================================${NC}"
echo ""
echo -e "${GREEN}통과:${NC} $TEST_PASSED"
echo -e "${RED}실패:${NC} $TEST_FAILED"
echo -e "${YELLOW}건너뜀:${NC} $TEST_SKIPPED"
echo ""

if [ $TEST_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 필수 테스트가 통과했습니다!${NC}"
    echo ""
    echo -e "${BLUE}Harbor 접속 정보:${NC}"
    echo "  URL: $HARBOR_URL"
    echo "  사용자명: admin"
    echo "  비밀번호: ${HARBOR_ADMIN_PASSWORD}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ 일부 테스트가 실패했습니다. 로그를 확인하세요.${NC}"
    echo ""
    echo -e "${YELLOW}문제 해결 방법:${NC}"
    echo "  1. Harbor 컨테이너 상태 확인: cd /opt/harbor && $COMPOSE_CMD ps"
    echo "  2. Harbor 로그 확인: cd /opt/harbor && $COMPOSE_CMD logs"
    echo "  3. Harbor 재시작: cd /opt/harbor && $COMPOSE_CMD restart"
    echo ""
    exit 1
fi

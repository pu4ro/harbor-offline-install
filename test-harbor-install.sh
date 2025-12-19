#!/bin/bash

################################################################################
# Harbor 설치 통합 테스트 스크립트
# 모든 기능이 정상 동작하는지 확인
################################################################################

set -e

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

# 테스트 결과 요약
print_summary() {
    echo ""
    echo "=========================================="
    echo "테스트 결과 요약"
    echo "=========================================="
    echo -e "통과: ${GREEN}${TEST_PASSED}${NC}"
    echo -e "실패: ${RED}${TEST_FAILED}${NC}"
    echo -e "건너뜀: ${YELLOW}${TEST_SKIPPED}${NC}"
    echo "총 테스트: $((TEST_PASSED + TEST_FAILED + TEST_SKIPPED))"
    echo "=========================================="

    if [ $TEST_FAILED -eq 0 ]; then
        echo -e "${GREEN}모든 테스트 통과!${NC}"
        return 0
    else
        echo -e "${RED}일부 테스트 실패${NC}"
        return 1
    fi
}

log_info ""
log_info "=========================================="
log_info "Harbor 설치 통합 테스트 시작"
log_info "=========================================="
log_info ""

# 테스트 1: 필수 파일 존재 확인
log_test "테스트 1: 필수 파일 존재 확인"

FILES=(
    "Makefile"
    ".env"
    "env.example"
    "download-packages.sh"
    "create-package.sh"
    "generate-certs.sh"
    "add-harbor-ca.sh"
    "install-harbor-nerdctl.sh"
    "README-KR.md"
    "QUICK-START-KR.md"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        test_pass "파일 존재: $file"
    else
        test_fail "파일 없음: $file"
    fi
done

# 테스트 2: 스크립트 실행 권한 확인
log_test ""
log_test "테스트 2: 스크립트 실행 권한 확인"

for file in *.sh; do
    if [ -x "$file" ]; then
        test_pass "실행 가능: $file"
    else
        test_fail "실행 불가: $file"
    fi
done

# 테스트 3: .env 파일 검증
log_test ""
log_test "테스트 3: .env 파일 검증"

if [ -f ".env" ]; then
    source .env

    # 필수 변수 확인
    REQUIRED_VARS=(
        "HARBOR_VERSION"
        "HARBOR_HOSTNAME"
        "HARBOR_ADMIN_PASSWORD"
        "DOCKER_COMPOSE_VERSION"
    )

    for var in "${REQUIRED_VARS[@]}"; do
        if [ -n "${!var}" ]; then
            test_pass ".env 변수 설정됨: $var=${!var}"
        else
            test_fail ".env 변수 없음: $var"
        fi
    done
else
    test_fail ".env 파일 없음"
fi

# 테스트 4: Makefile 검증
log_test ""
log_test "테스트 4: Makefile 명령어 확인"

MAKE_TARGETS=(
    "help"
    "download"
    "package"
    "generate-certs"
    "install"
    "verify"
)

for target in "${MAKE_TARGETS[@]}"; do
    if make -n $target &>/dev/null; then
        test_pass "Makefile target 존재: $target"
    else
        test_fail "Makefile target 없음: $target"
    fi
done

# 테스트 5: 시스템 요구사항 확인
log_test ""
log_test "테스트 5: 시스템 요구사항 확인"

# OS 확인
if [ -f /etc/redhat-release ]; then
    OS_VERSION=$(cat /etc/redhat-release)
    test_pass "OS: $OS_VERSION"
else
    test_warn "RHEL/CentOS 계열이 아닙니다"
fi

# 필수 명령어 확인
REQUIRED_COMMANDS=(
    "tar"
    "wget"
    "curl"
    "md5sum"
    "sha256sum"
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v $cmd &>/dev/null; then
        test_pass "명령어 존재: $cmd"
    else
        test_fail "명령어 없음: $cmd"
    fi
done

# 컨테이너 런타임 확인
log_test ""
log_test "테스트 6: 컨테이너 런타임 확인"

RUNTIME_FOUND=false

if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    test_pass "Docker 설치됨: $DOCKER_VERSION"
    RUNTIME_FOUND=true
fi

if command -v nerdctl &>/dev/null; then
    NERDCTL_VERSION=$(nerdctl --version | head -1)
    test_pass "nerdctl 설치됨: $NERDCTL_VERSION"
    RUNTIME_FOUND=true
fi

if command -v containerd &>/dev/null; then
    CONTAINERD_VERSION=$(containerd --version)
    test_pass "containerd 설치됨: $CONTAINERD_VERSION"
    RUNTIME_FOUND=true
fi

if [ "$RUNTIME_FOUND" = false ]; then
    test_warn "컨테이너 런타임이 설치되지 않았습니다 (설치 스크립트가 설치할 것입니다)"
fi

# 테스트 7: 디스크 공간 확인
log_test ""
log_test "테스트 7: 디스크 공간 확인"

AVAILABLE_SPACE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
REQUIRED_SPACE=40

if [ "$AVAILABLE_SPACE" -ge "$REQUIRED_SPACE" ]; then
    test_pass "디스크 공간 충분: ${AVAILABLE_SPACE}GB (최소 ${REQUIRED_SPACE}GB 필요)"
else
    test_fail "디스크 공간 부족: ${AVAILABLE_SPACE}GB (최소 ${REQUIRED_SPACE}GB 필요)"
fi

# 테스트 8: 네트워크 확인 (온라인 환경인 경우)
log_test ""
log_test "테스트 8: 네트워크 연결 확인 (온라인 환경)"

if ping -c 1 8.8.8.8 &>/dev/null; then
    test_pass "인터넷 연결됨"

    # GitHub 접속 확인
    if curl -s --head https://github.com | head -n 1 | grep "HTTP/[1-2]" &>/dev/null; then
        test_pass "GitHub 접속 가능"
    else
        test_warn "GitHub 접속 불가 (방화벽 또는 프록시 확인 필요)"
    fi
else
    test_skip "인터넷 연결 없음 (오프라인 환경)"
fi

# 테스트 9: 방화벽 상태 확인
log_test ""
log_test "테스트 9: 방화벽 상태 확인"

if command -v firewall-cmd &>/dev/null; then
    if systemctl is-active --quiet firewalld; then
        test_pass "firewalld 실행 중"

        # 포트 확인
        if firewall-cmd --list-ports | grep -q "80/tcp\|443/tcp"; then
            test_pass "Harbor 포트 (80/443) 열림"
        else
            test_warn "Harbor 포트가 열려있지 않습니다 (설치 스크립트가 열 것입니다)"
        fi
    else
        test_skip "firewalld 실행되지 않음"
    fi
else
    test_skip "firewalld 설치되지 않음"
fi

# 테스트 10: SELinux 상태 확인
log_test ""
log_test "테스트 10: SELinux 상태 확인"

if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce)
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        test_warn "SELinux가 Enforcing 모드입니다 (Permissive 권장)"
    else
        test_pass "SELinux: $SELINUX_STATUS"
    fi
else
    test_skip "SELinux 명령어 없음"
fi

# 테스트 11: 인증서 생성 테스트
log_test ""
log_test "테스트 11: 인증서 생성 기능 테스트"

if command -v openssl &>/dev/null; then
    OPENSSL_VERSION=$(openssl version)
    test_pass "OpenSSL 설치됨: $OPENSSL_VERSION"

    # 임시 인증서 생성 테스트
    TEST_DIR=$(mktemp -d)
    cd $TEST_DIR

    if openssl genrsa -out test.key 2048 &>/dev/null; then
        test_pass "인증서 생성 가능"
        rm -f test.key
    else
        test_fail "인증서 생성 실패"
    fi

    cd - >/dev/null
    rm -rf $TEST_DIR
else
    test_fail "OpenSSL 설치되지 않음"
fi

# 테스트 12: Kubernetes 환경 확인
log_test ""
log_test "테스트 12: Kubernetes 환경 확인 (선택사항)"

if command -v kubectl &>/dev/null; then
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep gitVersion || echo "알 수 없음")
    test_pass "kubectl 설치됨: $KUBECTL_VERSION"

    # 클러스터 접속 확인
    if kubectl cluster-info &>/dev/null; then
        test_pass "K8s 클러스터 접속 가능"
    else
        test_skip "K8s 클러스터 접속 불가 (정상 - registry 용도로 사용)"
    fi
else
    test_skip "kubectl 설치되지 않음 (정상 - registry 용도로 사용)"
fi

# 테스트 13: make help 명령 테스트
log_test ""
log_test "테스트 13: make help 명령 실행"

if make help &>/dev/null; then
    test_pass "make help 실행 성공"
else
    test_fail "make help 실행 실패"
fi

# 테스트 14: 환경 변수 파싱 테스트
log_test ""
log_test "테스트 14: .env 파일 파싱 테스트"

if bash -c "source .env && echo \$HARBOR_VERSION" &>/dev/null; then
    test_pass ".env 파일 정상 파싱"
else
    test_fail ".env 파일 파싱 오류"
fi

# 테스트 15: 스크립트 문법 검증
log_test ""
log_test "테스트 15: 스크립트 문법 검증"

for script in *.sh; do
    if bash -n "$script" 2>/dev/null; then
        test_pass "문법 정상: $script"
    else
        test_fail "문법 오류: $script"
    fi
done

# 결과 출력
print_summary

exit $?

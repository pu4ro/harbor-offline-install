.PHONY: help

# 색상 정의
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
RED    := \033[0;31m
NC     := \033[0m

# 기본 변수
PACKAGE_DIR := harbor-offline-packages
DATE := $(shell date +%Y%m%d)
PACKAGE_NAME := harbor-offline-rhel96-$(DATE).tar.gz

##@ 도움말

help: ## 도움말 표시
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "Harbor 오프라인 설치 관리 도구"
	@echo "nerdctl/containerd 전용 (Docker 제외)"
	@echo "==========================================$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ 1. 사전 준비

check: ## 시스템 요구사항 확인
	@echo "$(GREEN)[CHECK]$(NC) 시스템 요구사항 확인 중..."
	@echo ""
	@echo "$(YELLOW)필수 도구 확인:$(NC)"
	@command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || (echo "$(RED)✗ wget 또는 curl이 필요합니다$(NC)" && exit 1)
	@echo "$(GREEN)✓$(NC) wget/curl 설치됨"
	@command -v tar >/dev/null 2>&1 || (echo "$(RED)✗ tar가 필요합니다$(NC)" && exit 1)
	@echo "$(GREEN)✓$(NC) tar 설치됨"
	@echo ""
	@echo "$(YELLOW)디스크 공간 확인:$(NC)"
	@df -h . | tail -1 | awk '{print "  사용 가능: " $$4}'
	@echo ""
	@echo "$(GREEN)[CHECK]$(NC) 모든 요구사항 충족"

init: ## 환경 설정 파일 생성
	@if [ ! -f .env ]; then \
		echo "$(GREEN)[INIT]$(NC) .env 파일 생성 중..."; \
		cp env.example .env; \
		echo "$(GREEN)✓$(NC) .env 파일 생성 완료"; \
		echo ""; \
		echo "$(YELLOW)다음 단계:$(NC)"; \
		echo "  vi .env  # HARBOR_HOSTNAME, 비밀번호 등 설정"; \
		echo ""; \
	else \
		echo "$(YELLOW)[WARN]$(NC) .env 파일이 이미 존재합니다."; \
	fi

##@ 2. 온라인 시스템 (다운로드)

download: check ## Harbor 패키지 다운로드 (Docker 제외)
	@echo "$(GREEN)[DOWNLOAD]$(NC) Harbor 패키지 다운로드 시작..."
	@chmod +x download-packages.sh
	@./download-packages.sh
	@echo ""
	@echo "$(GREEN)[DOWNLOAD]$(NC) 다운로드 완료!"

package: ## 다운로드한 파일을 단일 패키지로 압축
	@echo "$(GREEN)[PACKAGE]$(NC) 패키지 생성 중..."
	@if [ ! -d "$(PACKAGE_DIR)" ]; then \
		echo "$(RED)[ERROR]$(NC) $(PACKAGE_DIR) 디렉토리가 없습니다."; \
		echo "먼저 'make download'를 실행하세요."; \
		exit 1; \
	fi
	@chmod +x create-package.sh
	@./create-package.sh
	@echo ""
	@echo "$(GREEN)[PACKAGE]$(NC) 패키지 생성 완료!"
	@echo "파일: $(PACKAGE_NAME)"

quick-online: check download package ## 온라인 원클릭: check -> download -> package
	@echo ""
	@echo "$(GREEN)=========================================="
	@echo "온라인 시스템 작업 완료!"
	@echo "==========================================$(NC)"
	@echo ""
	@ls -lh harbor-offline-rhel96-*.tar.gz 2>/dev/null | tail -1
	@echo ""
	@echo "$(YELLOW)다음 단계:$(NC)"
	@echo "  1. 패키지를 오프라인 시스템으로 전송"
	@echo "  2. 오프라인 시스템에서 'make quick-offline' 실행"

##@ 3. 인증서 관리 (HTTPS용)

generate-certs: ## HTTPS용 자체 서명 인증서 생성
	@echo "$(GREEN)[CERT]$(NC) 인증서 생성 중..."
	@chmod +x generate-certs.sh
	@./generate-certs.sh

install-certs: ## 인증서 설치 (오프라인 시스템)
	@echo "$(GREEN)[CERT-INSTALL]$(NC) 인증서 설치 중..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		echo "실행: sudo make install-certs"; \
		exit 1; \
	fi
	@if [ ! -d "harbor-certs" ]; then \
		CERT_PACKAGE=$$(ls harbor-certs-*.tar.gz 2>/dev/null | head -1); \
		if [ -z "$$CERT_PACKAGE" ]; then \
			echo "$(RED)[ERROR]$(NC) 인증서 패키지를 찾을 수 없습니다."; \
			exit 1; \
		fi; \
		tar -xzf $$CERT_PACKAGE; \
	fi
	@cd harbor-certs && chmod +x install-certs.sh && ./install-certs.sh

add-ca: ## 시스템에 Harbor CA 인증서 추가
	@echo "$(GREEN)[ADD-CA]$(NC) CA 인증서 추가 중..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		echo "실행: sudo make add-ca"; \
		exit 1; \
	fi
	@chmod +x add-harbor-ca.sh
	@if [ -f "harbor-certs/ca.crt" ]; then \
		HARBOR_HOST=$$(grep HARBOR_HOSTNAME .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "192.168.1.100"); \
		./add-harbor-ca.sh harbor-certs/ca.crt $$HARBOR_HOST; \
	else \
		echo "$(RED)[ERROR]$(NC) CA 인증서를 찾을 수 없습니다."; \
		echo "실행: make generate-certs"; \
		exit 1; \
	fi

##@ 4. 오프라인 시스템 (설치)

extract: ## 패키지 압축 해제
	@echo "$(GREEN)[EXTRACT]$(NC) 패키지 압축 해제 중..."
	@PACKAGE=$$(ls harbor-offline-rhel96-*.tar.gz 2>/dev/null | head -1); \
	if [ -z "$$PACKAGE" ]; then \
		echo "$(RED)[ERROR]$(NC) 패키지 파일을 찾을 수 없습니다."; \
		exit 1; \
	fi; \
	echo "패키지: $$PACKAGE"; \
	tar -xzf $$PACKAGE
	@echo "$(GREEN)[EXTRACT]$(NC) 압축 해제 완료!"

install: ## Harbor 오프라인 설치 (root 권한 필요)
	@echo "$(GREEN)[INSTALL]$(NC) Harbor 설치 시작..."
	@if [ ! -d "$(PACKAGE_DIR)" ]; then \
		echo "$(RED)[ERROR]$(NC) $(PACKAGE_DIR) 디렉토리가 없습니다."; \
		echo "먼저 'make extract'를 실행하세요."; \
		exit 1; \
	fi
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		echo "실행: sudo make install"; \
		exit 1; \
	fi
	@cd $(PACKAGE_DIR) && chmod +x install-offline.sh && ./install-offline.sh

verify: ## 설치 확인
	@echo "$(GREEN)[VERIFY]$(NC) 설치 검증 중..."
	@if [ -f "$(PACKAGE_DIR)/verify-installation.sh" ]; then \
		cd $(PACKAGE_DIR) && chmod +x verify-installation.sh && ./verify-installation.sh; \
	else \
		echo "$(YELLOW)[INFO]$(NC) 수동 확인:"; \
		echo "  - nerdctl --version"; \
		echo "  - systemctl status containerd"; \
		echo "  - docker-compose --version"; \
		echo "  - ls -la /opt/harbor"; \
	fi

quick-offline: extract install verify ## 오프라인 원클릭: extract -> install -> verify
	@echo ""
	@echo "$(GREEN)=========================================="
	@echo "오프라인 설치 완료!"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)다음 단계:$(NC)"
	@echo "  cd /opt/harbor"
	@echo "  cp harbor.yml.tmpl harbor.yml"
	@echo "  vi harbor.yml  # hostname, 비밀번호 설정"
	@echo "  ./prepare"
	@echo "  nerdctl compose up -d"
	@echo ""
	@echo "$(YELLOW)또는 자동 설치:$(NC)"
	@echo "  make harbor-auto-install"

##@ 5. Harbor 설치 및 설정

harbor-auto-install: ## Harbor 자동 설치 (nerdctl 사용)
	@echo "$(GREEN)[HARBOR-INSTALL]$(NC) Harbor 자동 설치 중..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		echo "실행: sudo make harbor-auto-install"; \
		exit 1; \
	fi
	@chmod +x install-harbor-nerdctl.sh
	@./install-harbor-nerdctl.sh

harbor-config: ## Harbor 설정 예제 표시
	@echo "$(GREEN)[CONFIG]$(NC) Harbor 설정 예제:"
	@echo ""
	@if [ -f "harbor-config-example.yml" ]; then \
		cat harbor-config-example.yml; \
	else \
		echo "$(YELLOW)[WARN]$(NC) harbor-config-example.yml를 찾을 수 없습니다."; \
	fi

##@ 6. Harbor 서비스 관리

harbor-start: ## Harbor 서비스 시작
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 시작 중..."
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose up -d
	@sleep 3
	@cd /opt/harbor && nerdctl compose ps

harbor-stop: ## Harbor 서비스 중지
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 중지 중..."
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose down

harbor-restart: ## Harbor 서비스 재시작
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 재시작 중..."
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose restart
	@sleep 3
	@cd /opt/harbor && nerdctl compose ps

harbor-status: ## Harbor 서비스 상태 확인
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 상태:"
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose ps

harbor-logs: ## Harbor 로그 확인 (Ctrl+C로 종료)
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose logs -f

##@ 7. containerd 설정

configure-containerd: ## containerd 자동 설정 (Harbor 레지스트리 사용)
	@echo "$(GREEN)[CONTAINERD]$(NC) containerd 설정 중..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		echo "실행: sudo make configure-containerd"; \
		exit 1; \
	fi
	@chmod +x configure-containerd.sh
	@./configure-containerd.sh

##@ 8. 테스트 및 검증

harbor-test: ## Harbor 자동 테스트 실행
	@echo "$(GREEN)[TEST]$(NC) Harbor 테스트 실행 중..."
	@chmod +x harbor-post-install-test.sh
	@./harbor-post-install-test.sh

test-all: check verify harbor-test ## 전체 테스트 실행

##@ 9. 이미지 관리

export-images: ## Harbor 이미지 export (오프라인 패키징용)
	@echo "$(GREEN)[EXPORT]$(NC) Harbor 이미지 export 중..."
	@chmod +x export-harbor-images.sh
	@./export-harbor-images.sh

import-images: ## Harbor 이미지 import
	@echo "$(GREEN)[IMPORT]$(NC) Harbor 이미지 import 중..."
	@if [ -d "$(PACKAGE_DIR)/harbor-images" ]; then \
		cd $(PACKAGE_DIR)/harbor-images && chmod +x import-images.sh && ./import-images.sh; \
	else \
		echo "$(RED)[ERROR]$(NC) harbor-images 디렉토리를 찾을 수 없습니다."; \
		exit 1; \
	fi

##@ 10. 유틸리티

info: ## 시스템 및 Harbor 정보 표시
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "시스템 정보"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)운영체제:$(NC)"
	@cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME
	@echo ""
	@echo "$(YELLOW)nerdctl:$(NC)"
	@nerdctl --version 2>/dev/null | head -1 || echo "  $(RED)설치되지 않음$(NC)"
	@echo ""
	@echo "$(YELLOW)containerd:$(NC)"
	@systemctl is-active --quiet containerd && echo "  $(GREEN)실행 중$(NC)" || echo "  $(RED)중지됨$(NC)"
	@echo ""
	@echo "$(YELLOW)Docker Compose:$(NC)"
	@docker-compose --version 2>/dev/null || echo "  $(RED)설치되지 않음$(NC)"
	@echo ""
	@if [ -d "/opt/harbor" ]; then \
		echo "$(YELLOW)Harbor:$(NC)"; \
		echo "  $(GREEN)설치됨$(NC) (/opt/harbor)"; \
	else \
		echo "$(YELLOW)Harbor:$(NC)"; \
		echo "  $(RED)설치되지 않음$(NC)"; \
	fi
	@echo ""

clean: ## 다운로드한 파일 정리
	@echo "$(YELLOW)[CLEAN]$(NC) 정리 대상:"
	@echo "  - $(PACKAGE_DIR)/"
	@echo "  - harbor-offline-rhel96-*.tar.gz"
	@echo "  - harbor-certs/"
	@echo "  - harbor-certs-*.tar.gz"
	@echo ""
	@read -p "계속하시겠습니까? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf $(PACKAGE_DIR); \
		rm -f harbor-offline-rhel96-*.tar.gz*; \
		rm -f harbor-certs-*.tar.gz; \
		rm -rf harbor-certs; \
		echo "$(GREEN)[CLEAN]$(NC) 정리 완료!"; \
	else \
		echo "$(YELLOW)[CLEAN]$(NC) 취소됨"; \
	fi

docs: ## 문서 목록 표시
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "문서 목록"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(GREEN)사용 가능한 문서:$(NC)"
	@if [ -f "README-KR.md" ]; then echo "  ✓ README-KR.md (상세 설치 가이드)"; fi
	@if [ -f "QUICKSTART.md" ]; then echo "  ✓ QUICKSTART.md (빠른 시작)"; fi
	@if [ -f "CLAUDE.md" ]; then echo "  ✓ CLAUDE.md (개발자 가이드)"; fi
	@if [ -f "OFFLINE-INSTALL.md" ]; then echo "  ✓ OFFLINE-INSTALL.md (오프라인 설치 가이드)"; fi
	@echo ""

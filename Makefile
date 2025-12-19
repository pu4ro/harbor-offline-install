.PHONY: help download package generate-certs clean check install verify all

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

##@ 일반 명령어

help: ## 도움말 표시
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "Harbor 오프라인 설치 관리 도구"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(GREEN)사용 가능한 명령어:$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "설치 워크플로우"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(GREEN)온라인 시스템에서:$(NC)"
	@echo "  1. make download          # 패키지 다운로드"
	@echo "  2. make generate-certs    # HTTPS용 인증서 생성 (선택)"
	@echo "  3. make package          # 단일 패키지로 압축"
	@echo ""
	@echo "$(GREEN)오프라인 시스템으로 전송:$(NC)"
	@echo "  - USB 또는 SCP로 패키지 전송"
	@echo ""
	@echo "$(GREEN)오프라인 시스템에서:$(NC)"
	@echo "  4. make extract          # 패키지 압축 해제"
	@echo "  5. make install          # Harbor 설치"
	@echo "  6. make verify           # 설치 확인"
	@echo ""
	@echo "$(BLUE)추가 정보:$(NC)"
	@echo "  - README-KR.md: 상세한 설치 가이드"
	@echo "  - INSTALL-GUIDE-KR.txt: 빠른 설치 가이드"
	@echo ""

all: check download package ## 모든 단계 실행 (check -> download -> package)

##@ 온라인 시스템 (다운로드)

check: ## 시스템 요구사항 확인
	@echo "$(GREEN)[CHECK]$(NC) 시스템 요구사항 확인 중..."
	@echo ""
	@echo "$(YELLOW)필수 도구 확인:$(NC)"
	@command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || (echo "$(RED)✗ wget 또는 curl이 필요합니다$(NC)" && exit 1)
	@echo "$(GREEN)✓$(NC) wget/curl 설치됨"
	@command -v tar >/dev/null 2>&1 || (echo "$(RED)✗ tar가 필요합니다$(NC)" && exit 1)
	@echo "$(GREEN)✓$(NC) tar 설치됨"
	@command -v md5sum >/dev/null 2>&1 || (echo "$(RED)✗ md5sum이 필요합니다$(NC)" && exit 1)
	@echo "$(GREEN)✓$(NC) md5sum 설치됨"
	@command -v sha256sum >/dev/null 2>&1 || (echo "$(RED)✗ sha256sum이 필요합니다$(NC)" && exit 1)
	@echo "$(GREEN)✓$(NC) sha256sum 설치됨"
	@echo ""
	@echo "$(YELLOW)디스크 공간 확인:$(NC)"
	@df -h . | tail -1 | awk '{print "  사용 가능: " $$4}'
	@echo ""
	@echo "$(GREEN)[CHECK]$(NC) 모든 요구사항이 충족되었습니다."
	@echo ""

download: check ## Harbor 및 의존성 패키지 다운로드
	@echo "$(GREEN)[DOWNLOAD]$(NC) 패키지 다운로드 시작..."
	@chmod +x download-packages.sh
	@./download-packages.sh
	@echo ""
	@echo "$(GREEN)[DOWNLOAD]$(NC) 다운로드 완료!"
	@echo ""

generate-certs: ## HTTPS용 자체 서명 인증서 생성
	@echo "$(GREEN)[CERT]$(NC) 자체 서명 인증서 생성..."
	@chmod +x generate-certs.sh
	@./generate-certs.sh
	@echo ""
	@echo "$(GREEN)[CERT]$(NC) 인증서 생성 완료!"
	@echo ""

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
	@echo ""

##@ 오프라인 시스템 (설치)

extract: ## 패키지 압축 해제
	@echo "$(GREEN)[EXTRACT]$(NC) 패키지 압축 해제 중..."
	@if [ ! -f "extract-and-install.sh" ]; then \
		PACKAGE=$$(ls harbor-offline-rhel96-*.tar.gz 2>/dev/null | head -1); \
		if [ -z "$$PACKAGE" ]; then \
			echo "$(RED)[ERROR]$(NC) 패키지 파일을 찾을 수 없습니다."; \
			exit 1; \
		fi; \
		echo "패키지: $$PACKAGE"; \
		tar -xzf $$PACKAGE; \
	else \
		chmod +x extract-and-install.sh; \
		./extract-and-install.sh; \
	fi
	@echo ""
	@echo "$(GREEN)[EXTRACT]$(NC) 압축 해제 완료!"
	@echo ""

install: ## Harbor 오프라인 설치 (root 권한 필요)
	@echo "$(GREEN)[INSTALL]$(NC) Harbor 설치 시작..."
	@if [ ! -d "$(PACKAGE_DIR)" ]; then \
		echo "$(RED)[ERROR]$(NC) $(PACKAGE_DIR) 디렉토리가 없습니다."; \
		echo "먼저 'make extract'를 실행하세요."; \
		exit 1; \
	fi
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) 이 명령은 root 권한이 필요합니다."; \
		echo "다음 명령을 실행하세요: sudo make install"; \
		exit 1; \
	fi
	@cd $(PACKAGE_DIR) && chmod +x install-offline.sh && ./install-offline.sh
	@echo ""
	@echo "$(GREEN)[INSTALL]$(NC) 설치 완료!"
	@echo ""
	@echo "$(YELLOW)다음 단계:$(NC)"
	@echo "  1. cd /opt/harbor"
	@echo "  2. cp harbor.yml.tmpl harbor.yml"
	@echo "  3. vi harbor.yml (설정 편집)"
	@echo "  4. ./install.sh"
	@echo ""

verify: ## 설치 확인
	@echo "$(GREEN)[VERIFY]$(NC) 설치 검증 중..."
	@if [ -f "$(PACKAGE_DIR)/verify-installation.sh" ]; then \
		cd $(PACKAGE_DIR) && chmod +x verify-installation.sh && ./verify-installation.sh; \
	else \
		echo "$(YELLOW)[WARN]$(NC) verify-installation.sh를 찾을 수 없습니다."; \
		echo "수동으로 확인:"; \
		echo "  - docker --version"; \
		echo "  - docker-compose --version"; \
		echo "  - systemctl status docker"; \
		echo "  - cd /opt/harbor && docker-compose ps"; \
	fi
	@echo ""

install-certs: ## 인증서 설치 (HTTPS 사용 시)
	@echo "$(GREEN)[CERT-INSTALL]$(NC) 인증서 설치 중..."
	@if [ ! -d "harbor-certs" ]; then \
		CERT_PACKAGE=$$(ls harbor-certs-*.tar.gz 2>/dev/null | head -1); \
		if [ -z "$$CERT_PACKAGE" ]; then \
			echo "$(RED)[ERROR]$(NC) 인증서 패키지를 찾을 수 없습니다."; \
			echo "먼저 'make generate-certs'를 실행하세요."; \
			exit 1; \
		fi; \
		tar -xzf $$CERT_PACKAGE; \
	fi
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) 이 명령은 root 권한이 필요합니다."; \
		echo "다음 명령을 실행하세요: sudo make install-certs"; \
		exit 1; \
	fi
	@cd harbor-certs && chmod +x install-certs.sh && ./install-certs.sh
	@echo ""
	@echo "$(GREEN)[CERT-INSTALL]$(NC) 인증서 설치 완료!"
	@echo ""

add-ca: ## 시스템에 Harbor CA 인증서 추가 (insecure registry 문제 해결)
	@echo "$(GREEN)[ADD-CA]$(NC) Harbor CA 인증서를 시스템에 추가..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) 이 명령은 root 권한이 필요합니다."; \
		echo "다음 명령을 실행하세요: sudo make add-ca"; \
		exit 1; \
	fi
	@if [ ! -f "add-harbor-ca.sh" ]; then \
		echo "$(RED)[ERROR]$(NC) add-harbor-ca.sh 스크립트를 찾을 수 없습니다."; \
		exit 1; \
	fi
	@chmod +x add-harbor-ca.sh
	@if [ -f "harbor-certs/ca.crt" ]; then \
		HARBOR_HOST=$$(grep HARBOR_HOSTNAME .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "192.168.1.100"); \
		./add-harbor-ca.sh harbor-certs/ca.crt $$HARBOR_HOST; \
	else \
		echo "$(YELLOW)[WARN]$(NC) CA 인증서를 찾을 수 없습니다."; \
		echo "사용법: sudo ./add-harbor-ca.sh <ca.crt 경로> <harbor-hostname>"; \
	fi
	@echo ""

##@ Harbor 관리

harbor-config: ## Harbor 설정 예제 표시
	@echo "$(GREEN)[CONFIG]$(NC) Harbor 설정 예제:"
	@echo ""
	@if [ -f "harbor-config-example.yml" ]; then \
		cat harbor-config-example.yml; \
	else \
		echo "$(YELLOW)[WARN]$(NC) harbor-config-example.yml 파일을 찾을 수 없습니다."; \
	fi
	@echo ""

harbor-start: ## Harbor 서비스 시작
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 시작 중..."
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose up -d
	@echo ""
	@echo "$(GREEN)[HARBOR]$(NC) Harbor가 시작되었습니다."
	@sleep 3
	@cd /opt/harbor && nerdctl compose ps
	@echo ""

harbor-stop: ## Harbor 서비스 중지
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 중지 중..."
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose down
	@echo ""
	@echo "$(GREEN)[HARBOR]$(NC) Harbor가 중지되었습니다."
	@echo ""

harbor-status: ## Harbor 서비스 상태 확인
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 상태 확인..."
	@echo ""
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose ps
	@echo ""

harbor-logs: ## Harbor 로그 확인
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 로그 표시..."
	@echo "$(YELLOW)(Ctrl+C로 종료)$(NC)"
	@echo ""
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose logs -f

harbor-restart: ## Harbor 서비스 재시작
	@echo "$(GREEN)[HARBOR]$(NC) Harbor 재시작 중..."
	@if [ ! -d "/opt/harbor" ]; then \
		echo "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose restart
	@echo ""
	@echo "$(GREEN)[HARBOR]$(NC) Harbor가 재시작되었습니다."
	@sleep 3
	@cd /opt/harbor && nerdctl compose ps
	@echo ""

harbor-test: ## Harbor 설치 후 자동 테스트 실행
	@echo "$(GREEN)[TEST]$(NC) Harbor 테스트 실행 중..."
	@if [ -f "harbor-post-install-test.sh" ]; then \
		chmod +x harbor-post-install-test.sh; \
		./harbor-post-install-test.sh; \
	else \
		echo "$(RED)[ERROR]$(NC) harbor-post-install-test.sh를 찾을 수 없습니다."; \
		exit 1; \
	fi

configure-containerd: ## containerd 설정 (Harbor 레지스트리 사용 설정)
	@echo "$(GREEN)[CONFIG]$(NC) containerd 설정 중..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "$(RED)[ERROR]$(NC) 이 명령은 root 권한이 필요합니다."; \
		echo "다음 명령을 실행하세요: sudo make configure-containerd"; \
		exit 1; \
	fi
	@if [ -f "configure-containerd.sh" ]; then \
		chmod +x configure-containerd.sh; \
		./configure-containerd.sh; \
	else \
		echo "$(RED)[ERROR]$(NC) configure-containerd.sh를 찾을 수 없습니다."; \
		exit 1; \
	fi

export-images: ## Harbor 이미지 export (오프라인 패키징용)
	@echo "$(GREEN)[EXPORT]$(NC) Harbor 이미지 export 중..."
	@if [ -f "export-harbor-images.sh" ]; then \
		chmod +x export-harbor-images.sh; \
		./export-harbor-images.sh; \
	else \
		echo "$(RED)[ERROR]$(NC) export-harbor-images.sh를 찾을 수 없습니다."; \
		exit 1; \
	fi

##@ 유틸리티

clean: ## 다운로드한 파일 및 임시 파일 정리
	@echo "$(YELLOW)[CLEAN]$(NC) 정리 중..."
	@echo ""
	@echo "다음 항목이 삭제됩니다:"
	@echo "  - $(PACKAGE_DIR)/"
	@echo "  - harbor-offline-rhel96-*.tar.gz"
	@echo "  - harbor-offline-rhel96-*.tar.gz.md5"
	@echo "  - harbor-offline-rhel96-*.tar.gz.sha256"
	@echo "  - harbor-certs/"
	@echo "  - harbor-certs-*.tar.gz"
	@echo "  - extract-and-install.sh"
	@echo ""
	@read -p "계속하시겠습니까? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf $(PACKAGE_DIR); \
		rm -f harbor-offline-rhel96-*.tar.gz*; \
		rm -f harbor-certs-*.tar.gz; \
		rm -rf harbor-certs; \
		rm -f extract-and-install.sh; \
		echo "$(GREEN)[CLEAN]$(NC) 정리 완료!"; \
	else \
		echo "$(YELLOW)[CLEAN]$(NC) 취소되었습니다."; \
	fi
	@echo ""

clean-all: clean ## 모든 파일 정리 (Harbor 설치 제외)
	@echo "$(YELLOW)[CLEAN-ALL]$(NC) 모든 임시 파일 정리 완료"

info: ## 시스템 및 패키지 정보 표시
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "시스템 정보"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)운영체제:$(NC)"
	@cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME
	@echo ""
	@echo "$(YELLOW)커널:$(NC)"
	@uname -r
	@echo ""
	@echo "$(YELLOW)디스크 사용량:$(NC)"
	@df -h . | tail -1 | awk '{print "  전체: " $$2 ", 사용: " $$3 ", 가용: " $$4 " (" $$5 ")"}'
	@echo ""
	@echo "$(YELLOW)Docker:$(NC)"
	@docker --version 2>/dev/null || echo "  $(RED)설치되지 않음$(NC)"
	@echo ""
	@echo "$(YELLOW)Docker Compose:$(NC)"
	@docker-compose --version 2>/dev/null || echo "  $(RED)설치되지 않음$(NC)"
	@echo ""
	@if [ -d "$(PACKAGE_DIR)" ]; then \
		echo "$(YELLOW)다운로드 패키지:$(NC)"; \
		du -sh $(PACKAGE_DIR); \
		echo ""; \
	fi
	@if [ -f "harbor-offline-rhel96-$(DATE).tar.gz" ]; then \
		echo "$(YELLOW)압축 패키지:$(NC)"; \
		ls -lh harbor-offline-rhel96-*.tar.gz | awk '{print "  " $$9 " (" $$5 ")"}'; \
		echo ""; \
	fi
	@if [ -d "/opt/harbor" ]; then \
		echo "$(YELLOW)Harbor 설치:$(NC)"; \
		echo "  $(GREEN)설치됨$(NC) (/opt/harbor)"; \
		echo ""; \
	fi
	@echo "$(BLUE)==========================================$(NC)"
	@echo ""

docs: ## 문서 표시
	@echo ""
	@echo "$(BLUE)=========================================="
	@echo "문서 목록"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(GREEN)사용 가능한 문서:$(NC)"
	@echo ""
	@if [ -f "README-KR.md" ]; then echo "  ✓ README-KR.md (상세 설치 가이드)"; fi
	@if [ -f "$(PACKAGE_DIR)/INSTALL-GUIDE-KR.txt" ]; then echo "  ✓ INSTALL-GUIDE-KR.txt (빠른 설치 가이드)"; fi
	@if [ -f "harbor-config-example.yml" ]; then echo "  ✓ harbor-config-example.yml (설정 예제)"; fi
	@echo ""
	@echo "$(YELLOW)문서 보기:$(NC)"
	@if [ -f "README-KR.md" ]; then echo "  cat README-KR.md"; fi
	@if [ -f "$(PACKAGE_DIR)/INSTALL-GUIDE-KR.txt" ]; then echo "  cat $(PACKAGE_DIR)/INSTALL-GUIDE-KR.txt"; fi
	@if [ -f "harbor-config-example.yml" ]; then echo "  cat harbor-config-example.yml"; fi
	@echo ""

##@ 빠른 시작

quick-online: check download package ## 온라인 시스템에서 빠른 시작 (다운로드 + 패키징)
	@echo ""
	@echo "$(GREEN)=========================================="
	@echo "온라인 시스템 작업 완료!"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)다음 단계:$(NC)"
	@echo "1. 생성된 패키지를 오프라인 시스템으로 전송"
	@echo "2. 오프라인 시스템에서 'make quick-offline' 실행"
	@echo ""

quick-offline: extract install verify ## 오프라인 시스템에서 빠른 시작 (압축 해제 + 설치 + 검증)
	@echo ""
	@echo "$(GREEN)=========================================="
	@echo "오프라인 설치 완료!"
	@echo "==========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)다음 단계:$(NC)"
	@echo "  cd /opt/harbor"
	@echo "  cp harbor.yml.tmpl harbor.yml"
	@echo "  vi harbor.yml"
	@echo "  ./install.sh"
	@echo ""

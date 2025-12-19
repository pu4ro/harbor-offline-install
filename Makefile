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
	@printf "\n"
	@printf "$(BLUE)==========================================\n"
	@printf "Harbor 오프라인 설치 관리 도구\n"
	@printf "nerdctl/containerd 전용 (Docker 제외)\n"
	@printf "==========================================$(NC)\n"
	@printf "\n"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@printf "\n"

##@ 1. 사전 준비

check: ## 시스템 요구사항 확인
	@printf "$(GREEN)[CHECK]$(NC) 시스템 요구사항 확인 중...\n"
	@printf "\n"
	@printf "$(YELLOW)필수 도구 확인:$(NC)\n"
	@command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || (printf "$(RED)✗ wget 또는 curl이 필요합니다$(NC)\n" && exit 1)
	@printf "$(GREEN)✓$(NC) wget/curl 설치됨\n"
	@command -v tar >/dev/null 2>&1 || (printf "$(RED)✗ tar가 필요합니다$(NC)\n" && exit 1)
	@printf "$(GREEN)✓$(NC) tar 설치됨\n"
	@printf "\n"
	@printf "$(YELLOW)디스크 공간 확인:$(NC)\n"
	@df -h . | tail -1 | awk '{print "  사용 가능: " $$4}'
	@printf "\n"
	@printf "$(GREEN)[CHECK]$(NC) 모든 요구사항 충족\n"

init: ## 환경 설정 파일 생성
	@if [ ! -f .env ]; then \
		printf "$(GREEN)[INIT]$(NC) .env 파일 생성 중...\n"; \
		cp env.example .env; \
		printf "$(GREEN)✓$(NC) .env 파일 생성 완료\n"; \
		printf "\n"; \
		printf "$(YELLOW)다음 단계:$(NC)\n"; \
		printf "  vi .env  # HARBOR_HOSTNAME, 비밀번호 등 설정\n"; \
		printf "\n"; \
	else \
		printf "$(YELLOW)[WARN]$(NC) .env 파일이 이미 존재합니다.\n"; \
	fi

##@ 2. 온라인 시스템 (다운로드)

download: check ## Harbor 패키지 다운로드 (Docker 제외)
	@printf "$(GREEN)[DOWNLOAD]$(NC) Harbor 패키지 다운로드 시작...\n"
	@chmod +x download-packages.sh
	@./download-packages.sh
	@printf "\n"
	@printf "$(GREEN)[DOWNLOAD]$(NC) 다운로드 완료!\n"

package: ## 다운로드한 파일을 단일 패키지로 압축
	@printf "$(GREEN)[PACKAGE]$(NC) 패키지 생성 중...\n"
	@if [ ! -d "$(PACKAGE_DIR)" ]; then \
		printf "$(RED)[ERROR]$(NC) $(PACKAGE_DIR) 디렉토리가 없습니다."; \
		printf "먼저 'make download'를 실행하세요."; \
		exit 1; \
	fi
	@chmod +x create-package.sh
	@./create-package.sh
	@printf "\n"
	@printf "$(GREEN)[PACKAGE]$(NC) 패키지 생성 완료!\n"
	@printf "파일: $(PACKAGE_NAME)\n"

quick-online: check download package ## 온라인 원클릭: check -> download -> package
	@printf "\n"
	@printf "$(GREEN)==========================================\n"
	@printf "온라인 시스템 작업 완료!\n"
	@printf "==========================================$(NC)\n"
	@printf "\n"
	@ls -lh harbor-offline-rhel96-*.tar.gz 2>/dev/null | tail -1
	@printf "\n"
	@printf "$(YELLOW)다음 단계:$(NC)\n"
	@printf "  1. 패키지를 오프라인 시스템으로 전송\n"
	@printf "  2. 오프라인 시스템에서 'make quick-offline' 실행\n"

##@ 3. 인증서 관리 (HTTPS용)

generate-certs: ## HTTPS용 자체 서명 인증서 생성
	@printf "$(GREEN)[CERT]$(NC) 인증서 생성 중...\n"
	@chmod +x generate-certs.sh
	@./generate-certs.sh

install-certs: ## 인증서 설치 (오프라인 시스템)
	@printf "$(GREEN)[CERT-INSTALL]$(NC) 인증서 설치 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		printf "실행: sudo make install-certs"; \
		exit 1; \
	fi
	@if [ ! -d "harbor-certs" ]; then \
		CERT_PACKAGE=$$(ls harbor-certs-*.tar.gz 2>/dev/null | head -1); \
		if [ -z "$$CERT_PACKAGE" ]; then \
			printf "$(RED)[ERROR]$(NC) 인증서 패키지를 찾을 수 없습니다."; \
			exit 1; \
		fi; \
		tar -xzf $$CERT_PACKAGE; \
	fi
	@cd harbor-certs && chmod +x install-certs.sh && ./install-certs.sh

add-ca: ## 시스템에 Harbor CA 인증서 추가
	@printf "$(GREEN)[ADD-CA]$(NC) CA 인증서 추가 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		printf "실행: sudo make add-ca"; \
		exit 1; \
	fi
	@chmod +x add-harbor-ca.sh
	@if [ -f "harbor-certs/ca.crt" ]; then \
		HARBOR_HOST=$$(grep HARBOR_HOSTNAME .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "192.168.1.100"); \
		./add-harbor-ca.sh harbor-certs/ca.crt $$HARBOR_HOST; \
	else \
		printf "$(RED)[ERROR]$(NC) CA 인증서를 찾을 수 없습니다."; \
		printf "실행: make generate-certs"; \
		exit 1; \
	fi

##@ 4. 오프라인 시스템 (설치)

extract: ## 패키지 압축 해제
	@printf "$(GREEN)[EXTRACT]$(NC) 패키지 압축 해제 중...\n"
	@PACKAGE=$$(ls harbor-offline-rhel96-*.tar.gz 2>/dev/null | head -1); \
	if [ -z "$$PACKAGE" ]; then \
		printf "$(RED)[ERROR]$(NC) 패키지 파일을 찾을 수 없습니다."; \
		exit 1; \
	fi; \
	printf "패키지: $$PACKAGE"; \
	tar -xzf $$PACKAGE
	@printf "$(GREEN)[EXTRACT]$(NC) 압축 해제 완료!\n"

install: ## Harbor 오프라인 설치 (root 권한 필요)
	@printf "$(GREEN)[INSTALL]$(NC) Harbor 설치 시작...\n"
	@if [ ! -d "$(PACKAGE_DIR)" ]; then \
		printf "$(RED)[ERROR]$(NC) $(PACKAGE_DIR) 디렉토리가 없습니다."; \
		printf "먼저 'make extract'를 실행하세요."; \
		exit 1; \
	fi
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		printf "실행: sudo make install"; \
		exit 1; \
	fi
	@cd $(PACKAGE_DIR) && chmod +x install-offline.sh && ./install-offline.sh

verify: ## 설치 확인
	@printf "$(GREEN)[VERIFY]$(NC) 설치 검증 중...\n"
	@if [ -f "$(PACKAGE_DIR)/verify-installation.sh" ]; then \
		cd $(PACKAGE_DIR) && chmod +x verify-installation.sh && ./verify-installation.sh; \
	else \
		printf "$(YELLOW)[INFO]$(NC) 수동 확인:"; \
		printf "  - nerdctl --version"; \
		printf "  - systemctl status containerd"; \
		printf "  - docker-compose --version"; \
		printf "  - ls -la /opt/harbor"; \
	fi

quick-offline: extract install verify ## 오프라인 원클릭: extract -> install -> verify
	@printf "\n"
	@printf "$(GREEN)==========================================\n"
	@printf "오프라인 설치 완료!\n"
	@printf "==========================================$(NC)\n"
	@printf "\n"
	@printf "$(YELLOW)다음 단계:$(NC)\n"
	@printf "  cd /opt/harbor\n"
	@printf "  cp harbor.yml.tmpl harbor.yml\n"
	@printf "  vi harbor.yml  # hostname, 비밀번호 설정\n"
	@printf "  ./prepare\n"
	@printf "  nerdctl compose up -d\n"
	@printf "\n"
	@printf "$(YELLOW)또는 자동 설치:$(NC)\n"
	@printf "  make harbor-auto-install\n"

##@ 5. Harbor 설치 및 설정

harbor-auto-install: ## Harbor 자동 설치 (nerdctl 사용)
	@printf "$(GREEN)[HARBOR-INSTALL]$(NC) Harbor 자동 설치 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		printf "실행: sudo make harbor-auto-install"; \
		exit 1; \
	fi
	@chmod +x install-harbor-nerdctl.sh
	@./install-harbor-nerdctl.sh

harbor-config: ## Harbor 설정 예제 표시
	@printf "$(GREEN)[CONFIG]$(NC) Harbor 설정 예제:\n"
	@printf "\n"
	@if [ -f "harbor-config-example.yml" ]; then \
		cat harbor-config-example.yml; \
	else \
		printf "$(YELLOW)[WARN]$(NC) harbor-config-example.yml를 찾을 수 없습니다."; \
	fi

##@ 6. Harbor 서비스 관리

harbor-start: ## Harbor 서비스 시작
	@printf "$(GREEN)[HARBOR]$(NC) Harbor 시작 중...\n"
	@if [ ! -d "/opt/harbor" ]; then \
		printf "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose up -d
	@sleep 3
	@cd /opt/harbor && nerdctl compose ps

harbor-stop: ## Harbor 서비스 중지
	@printf "$(GREEN)[HARBOR]$(NC) Harbor 중지 중...\n"
	@if [ ! -d "/opt/harbor" ]; then \
		printf "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose down

harbor-restart: ## Harbor 서비스 재시작
	@printf "$(GREEN)[HARBOR]$(NC) Harbor 재시작 중...\n"
	@if [ ! -d "/opt/harbor" ]; then \
		printf "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose restart
	@sleep 3
	@cd /opt/harbor && nerdctl compose ps

harbor-status: ## Harbor 서비스 상태 확인
	@printf "$(GREEN)[HARBOR]$(NC) Harbor 상태:\n"
	@if [ ! -d "/opt/harbor" ]; then \
		printf "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose ps

harbor-logs: ## Harbor 로그 확인 (Ctrl+C로 종료)
	@if [ ! -d "/opt/harbor" ]; then \
		printf "$(RED)[ERROR]$(NC) Harbor가 설치되지 않았습니다."; \
		exit 1; \
	fi
	@cd /opt/harbor && nerdctl compose logs -f

harbor-enable-service: ## Harbor systemd 서비스 활성화
	@printf "$(GREEN)[SYSTEMD]$(NC) Harbor systemd 서비스 활성화 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다.\n"; \
		printf "실행: sudo make harbor-enable-service\n"; \
		exit 1; \
	fi
	@systemctl enable harbor
	@systemctl start harbor
	@printf "$(GREEN)✓$(NC) Harbor 서비스 활성화 완료\n"
	@printf "\n"
	@systemctl status harbor --no-pager

harbor-disable-service: ## Harbor systemd 서비스 비활성화
	@printf "$(GREEN)[SYSTEMD]$(NC) Harbor systemd 서비스 비활성화 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다.\n"; \
		printf "실행: sudo make harbor-disable-service\n"; \
		exit 1; \
	fi
	@systemctl disable harbor
	@systemctl stop harbor
	@printf "$(GREEN)✓$(NC) Harbor 서비스 비활성화 완료\n"

##@ 7. containerd 설정

configure-containerd: ## containerd 자동 설정 (Harbor 레지스트리 사용)
	@printf "$(GREEN)[CONTAINERD]$(NC) containerd 설정 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다."; \
		printf "실행: sudo make configure-containerd"; \
		exit 1; \
	fi
	@chmod +x configure-containerd.sh
	@./configure-containerd.sh

##@ 8. 테스트 및 검증

harbor-test: ## Harbor 자동 테스트 실행
	@printf "$(GREEN)[TEST]$(NC) Harbor 테스트 실행 중...\n"
	@chmod +x harbor-post-install-test.sh
	@./harbor-post-install-test.sh

test-all: check verify harbor-test ## 전체 테스트 실행

##@ 9. 이미지 관리

export-images: ## Harbor 이미지 export (오프라인 패키징용)
	@printf "$(GREEN)[EXPORT]$(NC) Harbor 이미지 export 중...\n"
	@chmod +x export-harbor-images.sh
	@./export-harbor-images.sh

import-images: ## Harbor 이미지 import
	@printf "$(GREEN)[IMPORT]$(NC) Harbor 이미지 import 중...\n"
	@if [ -d "$(PACKAGE_DIR)/harbor-images" ]; then \
		cd $(PACKAGE_DIR)/harbor-images && chmod +x import-images.sh && ./import-images.sh; \
	else \
		printf "$(RED)[ERROR]$(NC) harbor-images 디렉토리를 찾을 수 없습니다."; \
		exit 1; \
	fi

##@ 10. Harbor 제거

harbor-uninstall: ## Harbor 완전 제거 (대화형)
	@printf "$(RED)[UNINSTALL]$(NC) Harbor 제거 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다.\n"; \
		printf "실행: sudo make harbor-uninstall\n"; \
		exit 1; \
	fi
	@chmod +x uninstall-harbor.sh
	@./uninstall-harbor.sh

harbor-clean-data: ## Harbor 데이터만 삭제
	@printf "$(RED)[CLEAN-DATA]$(NC) Harbor 데이터 삭제 중...\n"
	@if [ "$$(id -u)" -ne 0 ]; then \
		printf "$(RED)[ERROR]$(NC) root 권한이 필요합니다.\n"; \
		printf "실행: sudo make harbor-clean-data\n"; \
		exit 1; \
	fi
	@printf "$(YELLOW)[WARN]$(NC) 모든 Harbor 데이터가 삭제됩니다!\n"
	@read -p "계속하시겠습니까? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf /data; \
		printf "$(GREEN)✓$(NC) Harbor 데이터 삭제 완료\n"; \
	else \
		printf "$(YELLOW)취소됨$(NC)\n"; \
	fi

##@ 11. 유틸리티

info: ## 시스템 및 Harbor 정보 표시
	@printf "\n"
	@printf "$(BLUE)==========================================\n"
	@printf "시스템 정보\n"
	@printf "==========================================$(NC)\n"
	@printf "\n"
	@printf "$(YELLOW)운영체제:$(NC)\n"
	@cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME
	@printf "\n"
	@printf "$(YELLOW)nerdctl:$(NC)\n"
	@nerdctl --version 2>/dev/null | head -1 || echo "  $(RED)설치되지 않음$(NC)"
	@printf "\n"
	@printf "$(YELLOW)containerd:$(NC)\n"
	@systemctl is-active --quiet containerd && echo "  $(GREEN)실행 중$(NC)" || echo "  $(RED)중지됨$(NC)"
	@printf "\n"
	@printf "$(YELLOW)Docker Compose:$(NC)\n"
	@docker-compose --version 2>/dev/null || echo "  $(RED)설치되지 않음$(NC)"
	@printf "\n"
	@if [ -d "/opt/harbor" ]; then \
		printf "$(YELLOW)Harbor:$(NC)"; \
		printf "  $(GREEN)설치됨$(NC) (/opt/harbor)"; \
	else \
		printf "$(YELLOW)Harbor:$(NC)"; \
		printf "  $(RED)설치되지 않음$(NC)"; \
	fi
	@printf "\n"

clean: ## 다운로드한 파일 정리
	@printf "$(YELLOW)[CLEAN]$(NC) 정리 대상:\n"
	@printf "  - $(PACKAGE_DIR)/\n"
	@printf "  - harbor-offline-rhel96-*.tar.gz\n"
	@printf "  - harbor-certs/\n"
	@printf "  - harbor-certs-*.tar.gz\n"
	@printf "\n"
	@read -p "계속하시겠습니까? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf $(PACKAGE_DIR); \
		rm -f harbor-offline-rhel96-*.tar.gz*; \
		rm -f harbor-certs-*.tar.gz; \
		rm -rf harbor-certs; \
		printf "$(GREEN)[CLEAN]$(NC) 정리 완료!"; \
	else \
		printf "$(YELLOW)[CLEAN]$(NC) 취소됨"; \
	fi

docs: ## 문서 목록 표시
	@printf "\n"
	@printf "$(BLUE)==========================================\n"
	@printf "문서 목록\n"
	@printf "==========================================$(NC)\n"
	@printf "\n"
	@printf "$(GREEN)사용 가능한 문서:$(NC)\n"
	@if [ -f "README-KR.md" ]; then echo "  ✓ README-KR.md (상세 설치 가이드)"; fi
	@if [ -f "QUICKSTART.md" ]; then echo "  ✓ QUICKSTART.md (빠른 시작)"; fi
	@if [ -f "CLAUDE.md" ]; then echo "  ✓ CLAUDE.md (개발자 가이드)"; fi
	@if [ -f "OFFLINE-INSTALL.md" ]; then echo "  ✓ OFFLINE-INSTALL.md (오프라인 설치 가이드)"; fi
	@printf "\n"

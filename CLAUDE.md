# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Harbor offline installation toolkit for RHEL 9.6 environments. It automates the download, packaging, and installation of Harbor (a container registry) in air-gapped systems. The project supports both Docker and nerdctl/containerd runtimes, with optional HTTPS via self-signed certificates.

## Key Architecture

### Two-Phase Workflow
1. **Online Phase** (internet-connected system): Download Harbor packages, Docker RPMs, dependencies, and optionally generate TLS certificates
2. **Offline Phase** (air-gapped RHEL 9.6): Extract packages and install Harbor with all dependencies

### Configuration Management
- All settings centralized in `.env` file (copy from `env.example`)
- Environment variables control: Harbor version, hostname, passwords, HTTPS settings, container runtime choice
- Scripts load `.env` at runtime using `source .env` pattern

### Container Runtime Support
- **Docker mode** (default): Installs Docker Engine + Docker Compose, runs Harbor via `docker-compose`
- **nerdctl mode**: For K8s pre-installation scenarios where containerd is already present; uses `install-harbor-nerdctl.sh`
- Runtime detection: Scripts check for existing Docker/nerdctl and adapt behavior

## Essential Commands

### Development Workflow
```bash
# Create/edit configuration
cp env.example .env
vi .env  # Set HARBOR_HOSTNAME, passwords, versions, ENABLE_HTTPS

# Online system - download and package
make download          # Downloads Harbor offline installer, dependencies
make generate-certs    # (Optional) Generates self-signed CA and server certificates
make export-images    # (Optional) Export Harbor images for offline packaging
make package          # Creates harbor-offline-rhel96-YYYYMMDD.tar.gz

# Quick online workflow
make quick-online     # Runs: check -> download -> package

# Offline system - install
make extract          # Unpacks transferred package
sudo make install     # Runs install-offline.sh (requires root)
make verify          # Validates nerdctl/compose installation

# Quick offline workflow
sudo make quick-offline  # Runs: extract -> install -> verify

# Harbor service management (after Harbor's ./install.sh completes)
make harbor-start|stop|restart|status|logs
make harbor-test      # Automated post-install test (API, containers, projects)

# containerd/nerdctl configuration
sudo make configure-containerd  # Setup Harbor registry in containerd
```

### Testing
```bash
./test-harbor-install.sh  # Integration test - checks env vars, runtime detection, firewall/SELinux
make check               # Validates prerequisites (wget/curl, tar, md5sum, etc.)
make verify              # Post-install verification
```

### Certificate Management
```bash
make generate-certs   # Creates CA + server cert in harbor-certs/
make install-certs    # Installs certs on offline system (root required)
make add-ca          # Adds Harbor CA to system trust store + Docker/containerd config
```

## Code Structure & Patterns

### Root-Level Scripts (Bash)
- **download-packages.sh**: Downloads Harbor installer from GitHub, dependencies, creates `harbor-offline-packages/`
- **create-package.sh**: Tars up `harbor-offline-packages/` with checksums (MD5/SHA256), generates `extract-and-install.sh`
- **generate-certs.sh**: OpenSSL-based CA and server certificate generation with SAN support (supports domain names)
- **add-harbor-ca.sh**: Installs CA cert to system trust + configures containerd/nerdctl
- **install-harbor-nerdctl.sh**: nerdctl-specific Harbor installation, creates systemd service
- **test-harbor-install.sh**: Pre-installation test suite with `test_pass/test_fail/test_skip` functions
- **harbor-post-install-test.sh**: **NEW** - Automated post-install testing (API, containers, projects, HTTP/HTTPS)
- **export-harbor-images.sh**: **NEW** - Exports Harbor images as tar files for offline packaging
- **configure-containerd.sh**: **NEW** - Configures containerd for Harbor registry (HTTP/HTTPS, insecure/CA)

### Makefile Organization
- Targets grouped by phase: `##@ 온라인 시스템`, `##@ 오프라인 시스템`, `##@ Harbor 관리`
- Help text auto-generated from `##` comments via awk
- Color-coded output: `GREEN/YELLOW/RED/BLUE` ANSI escape codes
- Idempotency: Checks for required files/directories before proceeding

### Shell Script Conventions
- All scripts start with `#!/bin/bash` and `set -e` (exit on error)
- Logging functions: `log_info()`, `log_warn()`, `log_error()` with color codes
- Environment loading pattern: `set -a; source .env; set +a`
- Default values: `${VAR:-default}` pattern throughout
- Functions use snake_case, environment variables UPPERCASE

## Critical Implementation Details

### Environment Variable Precedence
Scripts load `.env` then apply defaults if vars are unset. When adding new config options:
1. Add to `env.example` with detailed comments
2. Apply default in script: `FOO="${FOO:-default_value}"`
3. Update relevant documentation (README-KR.md, QUICK-START-KR.md)

### Runtime Detection Logic
Scripts check for container runtimes in this order:
1. Read `CONTAINER_RUNTIME` from `.env` (auto/docker/nerdctl)
2. If "auto": check `command -v docker` then `command -v nerdctl`
3. Skip Docker installation if `SKIP_DOCKER_INSTALL=true`

### Certificate File Layout
```
harbor-certs/
├── ca.crt, ca.key          # CA certificate/key
├── server.crt, server.key  # Server certificate/key
├── harbor.crt, harbor.key  # Combined format for Harbor
└── install-certs.sh        # Generated installer script
```

### Package Structure
```
harbor-offline-packages/
├── harbor-offline-installer-*.tgz  # Harbor release from GitHub
├── docker-packages/                # Docker Engine RPMs
├── compose-linux-x86_64           # Docker Compose binary
└── install-offline.sh             # Main offline installer
```

## Documentation Files (Korean)
- **README-KR.md**: Comprehensive installation guide with all scenarios
- **QUICK-START-KR.md**: Fast-track guide for common use cases
- **README-K8S.md**: Kubernetes integration (imagePullSecrets, containerd config)
- **SUMMARY-KR.md**: Project overview and feature summary
- **AGENTS.md**: Development guidelines (commit style, code patterns, testing)

When updating installation logic, sync changes to README-KR.md and QUICK-START-KR.md.

## Security Considerations

### Secrets Management
- Never commit `.env`, `harbor-certs/`, or `*.tar.gz` packages (enforced by `.gitignore`)
- Default passwords in `env.example` are placeholders - warn users to change
- Certificates generated with 10-year validity by default (`CERT_VALIDITY_DAYS=3650`)

### Firewall & SELinux
- Scripts can auto-configure firewall: `firewall-cmd --permanent --add-service=http/https`
- SELinux handling: `DISABLE_SELINUX=true` option (sets permissive mode)
- Document manual steps if auto-config disabled

## New Features & Workflows

### Automated Post-Install Testing
After Harbor installation, run comprehensive tests:
```bash
make harbor-test  # Or: ./harbor-post-install-test.sh
```
Tests include:
- Container status (9 containers running)
- Web UI accessibility (HTTP/HTTPS)
- API authentication with admin credentials
- Project list retrieval
- Test project creation and verification
- Disk space check
- Log file access

### Harbor Image Packaging for Offline
To include Harbor container images in offline package:
```bash
# Online system (after Harbor is installed/running)
make export-images
# Creates harbor-offline-packages/harbor-images/*.tar

# Offline system
cd harbor-offline-packages/harbor-images
./import-images.sh  # Loads all images into nerdctl
```

### containerd Configuration for Harbor Registry
Automatically configure containerd to trust Harbor registry:
```bash
sudo make configure-containerd
```
This creates `/etc/containerd/certs.d/<harbor-host>/hosts.toml` with:
- HTTP mode: insecure registry settings
- HTTPS mode: CA certificate configuration
- Automatic containerd restart

### Domain Name Support
Harbor now fully supports domain names in addition to IP addresses:
1. Set `HARBOR_HOSTNAME=harbor.example.com` in `.env`
2. Generate certificates with SAN support: `make generate-certs`
3. Add additional domains via `CERT_ADDITIONAL_SANS=harbor.example.com,harbor-prod.example.com`

## Common Workflows

### Adding a New Make Target
1. Add target under appropriate `##@` section in Makefile
2. Include `##` comment for help text
3. Use color codes for output consistency
4. Check prerequisites (directory/file existence, root permissions)
5. Provide actionable next steps on success

### Adding Configuration Option
1. Add to `env.example` with clear comments and example values
2. Load in relevant script(s) with default fallback
3. Update harbor-config-example.yml if affects Harbor configuration
4. Test both set and unset scenarios

### Supporting New Harbor Version
1. Update `HARBOR_VERSION` in `env.example`
2. Test download-packages.sh with new version
3. Verify Harbor's install.sh compatibility
4. Update version references in documentation

## Dependencies & External Resources

- Harbor releases: https://github.com/goharbor/harbor/releases
- Docker Compose releases: https://github.com/docker/compose/releases
- RHEL 9 Docker packages: https://download.docker.com/linux/rhel/9/x86_64/stable/
- OpenSSL for certificate generation (system package)

## Build/Install Validation

Before committing changes that affect installation:
1. Run `make check` to verify prerequisites
2. Test online workflow: `make download package`
3. Test offline workflow: `make extract install verify` (requires VM/container)
4. Run `./test-harbor-install.sh` with populated `.env`
5. Verify Harbor UI accessible after Harbor's `./install.sh`

## Troubleshooting Notes

### Common Issues
- **"Package directory not found"**: User needs `make extract` before `make install`
- **"Root privileges required"**: Makefile checks `id -u != 0` for install targets
- **insecure-registry errors**: Client needs `make add-ca` or manual Docker daemon.json config
- **nerdctl compose not found**: Falls back to docker-compose binary

### Debug Patterns
- All scripts use `set -e` - to debug, add `set -x` temporarily
- Harbor logs: `make harbor-logs` or `cd /opt/harbor && docker-compose logs -f`
- Test script shows pass/fail/skip counts - investigate failures first

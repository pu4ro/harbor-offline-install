# Repository Guidelines

## Project Structure & Module Organization
- Root-level `Makefile` drives the offline workflow: download, package, extract, install, and Harbor service control.
- Workflow logic is in root shell scripts (`download-packages.sh`, `create-package.sh`, `generate-certs.sh`, `add-harbor-ca.sh`, `install-harbor-nerdctl.sh`); keep new helpers beside them.
- Configuration is `.env` (copy from `env.example`); Harbor host, version, and passwords come from there—avoid hardcoding.
- Docs are mainly Korean (`README-KR.md`, `QUICK-START-KR.md`, `README-K8S.md`) plus `harbor-config-example.yml`. Update docs when flows change.

## Build, Test, and Development Commands
- `make help` shows targets; `make check` validates prerequisites.
- Online host: `make download`, `make generate-certs` (optional HTTPS), `make package`.
- Offline host: `make extract`, `sudo make install`, `make verify`; `make harbor-start|stop|status|logs|restart` manage Harbor.
- `./test-harbor-install.sh` runs integration-style checks (env vars, runtime detection, firewall/SELinux notes); expect skips when offline.
- `make clean` removes packages/certs and helper artifacts—confirm before using on shared systems.

## Coding Style & Naming Conventions
- Bash scripts with `#!/bin/bash`; prefer `set -e` for installers, helper functions (`log_info`, `test_pass`), uppercase env vars, and snake_case locals.
- Keep commands idempotent and prompt on destructive actions (pattern in `make clean`).
- Make targets should be imperative, short, and annotated with `##` so they appear in `make help`.

## Testing Guidelines
- Before packaging, run `make check` and, when possible, `./test-harbor-install.sh` with a populated `.env`.
- After offline install, `make verify` (or `harbor-offline-packages/verify-installation.sh` if present) is the standard smoke test; extend it when you add dependencies or binaries.
- Validate new scripts with `bash -n script.sh` and add small functional probes mirroring the existing test script.

## Commit & Pull Request Guidelines
- Use concise, imperative commit subjects with an area tag (e.g., `make: add harbor restart`, `docs: refresh k8s steps`); expand details in the body.
- PRs should state which host role they target (online/offline), list key commands run, and note test results or skips. Link to updated docs and attach relevant logs for installer changes.

## Security & Configuration Tips
- Do not commit `.env`, generated certs, or packaged tarballs; keep examples in `env.example`/templates.
- Replace sample credentials like `HARBOR_ADMIN_PASSWORD` and hostnames before use, and remind users to do the same in docs.
- Prefer `make generate-certs`/`make install-certs` so paths match expectations; document any new ports or firewall rules.

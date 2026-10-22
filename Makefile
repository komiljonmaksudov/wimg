# wimg — one place for the everyday commands. Thin wrappers only: the real
# logic stays in scripts/ and infra/scripts/. Run `make` to list targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

SQLITE_ZIP :=https://www.sqlite.org/2026/sqlite-amalgamation-3520000.zip
SQLITE := libwimg/vendor/sqlite3.c

.PHONY: help dev dev-native wasm web ios android \
	test check fmt lint i18n \
	deploy deploy-web deploy-sync release-patch release-minor

help: ## List targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | \
		awk -F ':.*## ' '{ printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }'

# The amalgamation is gitignored; every native build needs it (see AGENTS.md).
$(SQLITE):
	@echo "==> Fetching SQLite amalgamation"
	@tmp=$$(mktemp -d) && \
		curl -fsSL $(SQLITE_ZIP) -o $$tmp/sqlite.zip && \
		unzip -q -o $$tmp/sqlite.zip -d $$tmp && \
		cp $$tmp/sqlite-amalgamation-3520000/sqlite3.{c,h} libwimg/vendor/ && \
		rm -rf $$tmp

# --- Dev ---------------------------------------------------------------------

dev: $(SQLITE) ## Sync server :8787 + web :5173
	./scripts/dev.sh

dev-native: $(SQLITE) ## Same, with the native Zig sync server
	WIMG_NATIVE_SYNC=1 ./scripts/dev.sh

# --- Build -------------------------------------------------------------------

wasm: ## Build both WASM variants (web + compact)
	./scripts/build-wasm.sh

web: wasm ## Build the static web app
	cd wimg-web && bun install --frozen-lockfile && bun run build

ios: $(SQLITE) ## Build XCFramework + regenerate the Xcode project
	./scripts/build-ios.sh
	./scripts/gen-xcodeproj.sh

android: $(SQLITE) ## Build libwimg.so + debug APK
	./scripts/build-android.sh
	cd wimg-android && { [ -x gradlew ] || gradle wrapper; } && ./gradlew assembleDebug

i18n: ## Regenerate iOS + Android translation tables from en.ts
	bun scripts/i18n-codegen.ts

# --- Quality (same gate as CI's check job) ------------------------------------

test: $(SQLITE) ## All tests: libwimg, sync server, web
	cd libwimg && zig build test
	cd wimg-sync-zig && zig build test
	cd wimg-web && bun test

check: fmt lint test ## fmt + lint + tests + svelte-check
	cd wimg-web && bun run check

fmt: ## Check formatting (zig fmt + oxfmt)
	cd libwimg && zig fmt --check src/
	cd wimg-web && bunx oxfmt --check

lint: ## oxlint
	cd wimg-web && bunx oxlint

# --- Ship --------------------------------------------------------------------

deploy: ## Build + push web app and sync server to the VPS
	./scripts/deploy-server.sh

deploy-web: ## Build + push only the web app
	./scripts/deploy-server.sh web

deploy-sync: ## Build + push only the sync server
	./scripts/deploy-server.sh sync

release-patch: ## Bump patch, tag, push (CI builds iOS/Android)
	./scripts/release.sh patch --push

release-minor: ## Bump minor, tag, push
	./scripts/release.sh minor --push

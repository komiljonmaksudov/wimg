# wimg — one place for the everyday commands. Thin wrappers only: the real
# logic stays in scripts/ and infra/scripts/. Run `make` to list targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

SQLITE_ZIP :=https://www.sqlite.org/2026/sqlite-amalgamation-3520000.zip
SQLITE := libwimg/vendor/sqlite3.c

.PHONY: help dev dev-native wasm ios android \
	test check fmt i18n \
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

dev: $(SQLITE) ## Sync server :8787 (Cloudflare Worker)
	./scripts/dev.sh

dev-native: $(SQLITE) ## Same, with the native Zig sync server
	WIMG_NATIVE_SYNC=1 ./scripts/dev.sh

# --- Build -------------------------------------------------------------------

wasm: ## Build the compact WASM for the wimg-sync worker
	./scripts/build-wasm.sh

ios: $(SQLITE) ## Build XCFramework + regenerate the Xcode project
	./scripts/build-ios.sh
	./scripts/gen-xcodeproj.sh

android: $(SQLITE) ## Build libwimg.so + debug APK
	./scripts/build-android.sh
	cd wimg-android && { [ -x gradlew ] || gradle wrapper; } && ./gradlew assembleDebug

i18n: ## Regenerate iOS + Android translation tables from en.ts
	bun scripts/i18n-codegen.ts

# --- Quality (same gate as CI's check job) ------------------------------------

test: $(SQLITE) ## All tests: libwimg, sync server
	cd libwimg && zig build test
	cd wimg-sync-zig && zig build test

check: fmt test ## fmt + tests + translation tables up to date
	bun scripts/i18n-codegen.ts && git diff --exit-code -- wimg-ios/plugins/WimgI18n wimg-android/app/src/main/java/com/wimg/app/i18n

fmt: ## Check formatting (zig fmt)
	cd libwimg && zig fmt --check src/
	cd wimg-sync-zig && zig fmt --check src/ build.zig

# --- Ship --------------------------------------------------------------------

deploy: ## Build + push landing page and sync server to the VPS
	./scripts/deploy-server.sh

deploy-web: ## Build + push only the landing page
	./scripts/deploy-server.sh web

deploy-sync: ## Build + push only the sync server
	./scripts/deploy-server.sh sync

release-patch: ## Bump patch, tag, push (CI builds iOS/Android)
	./scripts/release.sh patch --push

release-minor: ## Bump minor, tag, push
	./scripts/release.sh minor --push

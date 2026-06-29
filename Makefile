# GrokBuild - Makefile for easy local macOS builds
#
# Uses SwiftPM (no Xcode project required).
# See BUILDING.md for full packaging & signing instructions.
#
# Optional: copy .env.example to .env for local SIGN_IDENTITY / NOTARY_PROFILE / RELEASE_TYPE
SIGN_IDENTITY ?=
NOTARY_PROFILE ?= AC_PASSWORD
RELEASE_TYPE ?= unsigned
-include .env
# Makefile $(...) parsing breaks TEAMID in parentheses — read identity via shell instead.
ifneq (,$(wildcard .env))
  _dotenv_sign := $(shell grep -E '^SIGN_IDENTITY=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r')
  ifneq ($(_dotenv_sign),)
    override SIGN_IDENTITY := $(_dotenv_sign)
  endif
endif
export SIGN_IDENTITY NOTARY_PROFILE RELEASE_TYPE

# Usage:
#   make build          # Build Release binary with SwiftPM
#   make test           # Run unit tests
#   make run            # Build + launch the menu bar app
#   make app            # Package .app into dist/
#   make install        # Package .app and copy to /Applications/ (signs when SIGN_IDENTITY in .env)
#   make dmg            # Package .app + DMG (auto-notarizes if NOTARY_PROFILE set)
#   make signed         # Codesigned build
#   make notarize       # Notarize (NOTARY_PROFILE=...)
#   make release        # Local only: build + publish GitHub release (gh auth); or push a v* tag for CI
#   make open           # Restart + launch /Applications/GrokBuild.app

APP_NAME       ?= GrokBuild
SCHEME         ?= GrokBuild
CONFIGURATION  ?= Release

DIST_DIR       ?= dist
BUILD_DIR      ?= .build

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
NC     := \033[0m

.PHONY: help build build-debug test run run-debug run-app app install dmg dmg-package signed clean open notarize release

help: ## Show this help
	@echo "GrokBuild macOS Build Commands"
	@echo ""
	@echo "  $(YELLOW)make build$(NC)            Build release binary (SwiftPM)"
	@echo "  $(YELLOW)make build-debug$(NC)      Build debug binary (Simulate Updates menu)"
	@echo "  $(YELLOW)make test$(NC)             Run unit tests"
	@echo "  $(YELLOW)make run$(NC)              Build release + launch the menu bar app"
	@echo "  $(YELLOW)make run-debug$(NC)        Build debug + launch (dev tools, Simulate Updates)"
	@echo "  $(YELLOW)make app$(NC)              Package .app into dist/"
	@echo "  $(YELLOW)make install$(NC)          Package .app and copy to /Applications/ (signs if SIGN_IDENTITY in .env)"
	@echo "  $(YELLOW)make dmg$(NC)              Build .app + DMG (auto-notarizes + re-DMG if NOTARY_PROFILE set)"
	@echo "  $(YELLOW)make signed$(NC)           Codesigned release"
	@echo "  $(YELLOW)make notarize$(NC)         Notarize (NOTARY_PROFILE=...)"
	@echo "  $(YELLOW)make release$(NC)          Local only: build + publish GitHub release (or push v* tag for CI)"
	@echo "  $(YELLOW)make open$(NC)             Restart + launch /Applications/$(APP_NAME).app"
	@echo "  $(YELLOW)make clean$(NC)            Remove build artifacts"
	@echo ""
	@echo "See BUILDING.md for full packaging & signing instructions."
	@echo ""
	@echo "Quick start: make run"
	@echo "Notarize example: make dmg NOTARY_PROFILE=AC_PASSWORD SIGN_IDENTITY=..."
	@echo "Release example: make release   # uses RELEASE_TYPE from .env when set"
	@echo "Notarized release: make release RELEASE_TYPE=notarized SIGN_IDENTITY=... NOTARY_PROFILE=..."

build-debug: ## Build using SwiftPM (Debug) - includes Simulate Updates menu
	@echo "$(GREEN)==> Building $(APP_NAME) with SwiftPM (debug)...$(NC)"
	@swift build
	@chmod +x .build/debug/GrokBuild 2>/dev/null || true
	@chmod +x .build/debug/GrokBuildComputerUseMCP 2>/dev/null || true
	@mkdir -p .build/debug
	@cp -f GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png .build/debug/ 2>/dev/null || true
	@cp -f GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png .build/debug/ 2>/dev/null || true
	@cp -f GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png .build/debug/ 2>/dev/null || true
	@cp -f AppIcon.png .build/debug/ 2>/dev/null || true
	@echo "$(GREEN)==> Debug build complete. Use 'make run-debug' for Simulate Updates.$(NC)"

build: ## Build using SwiftPM (Release) - recommended
	@echo "$(GREEN)==> Building $(APP_NAME) with SwiftPM (release)...$(NC)"
	@swift build -c release
	@chmod +x .build/release/GrokBuild 2>/dev/null || true
	@chmod +x .build/release/GrokBuildComputerUseMCP 2>/dev/null || true
	@mkdir -p .build/release
	@cp -f GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png .build/release/ 2>/dev/null || true
	@cp -f GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png .build/release/ 2>/dev/null || true
	@cp -f GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png .build/release/ 2>/dev/null || true
	@cp -f AppIcon.png .build/release/ 2>/dev/null || true
	@echo "$(GREEN)==> Build complete. Use 'make run' to launch (or ./.build/release/GrokBuild directly).$(NC)"

test: ## Run unit tests
	@echo "$(GREEN)==> Running unit tests...$(NC)"
	@swift test

run: build ## Build release + launch the menu bar app
	@$(MAKE) run-app BUILD_CONFIG=release

run-debug: build-debug ## Build debug + launch (includes Simulate Updates menu)
	@$(MAKE) run-app BUILD_CONFIG=debug

run-app:
	@echo "$(GREEN)==> Packaging dev app bundle ($(BUILD_CONFIG))...$(NC)"
	@chmod +x scripts/build-dev-app.sh
	@BUILD_CONFIG=$(BUILD_CONFIG) ./scripts/build-dev-app.sh
	@echo "$(GREEN)==> Starting GrokBuild...$(NC)"
	@pkill -x GrokBuild 2>/dev/null || true
	@sleep 0.2
	@open "$(BUILD_DIR)/$(APP_NAME).app"
	@echo "$(GREEN)==> GrokBuild launched from .build/$(APP_NAME).app$(NC)"

dmg: ## Build the .app and package it into a DMG.
	@if [ -n "$(NOTARY_PROFILE)" ]; then \
		$(MAKE) notarize; \
		$(MAKE) dmg-package; \
	else \
		if [ -n "$(SIGN_IDENTITY)" ]; then \
			./scripts/build-macos-app.sh --sign "$(SIGN_IDENTITY)"; \
		else \
			./scripts/build-macos-app.sh; \
		fi; \
	fi

dmg-package: ## Package dist/$(APP_NAME).app into a DMG (no rebuild)
	@echo "$(GREEN)==> Packaging DMG from dist/$(APP_NAME).app...$(NC)"
	@DMG_PATH="dist/$(APP_NAME)-macOS.dmg"; \
	DMG_STAGING="dist/dmg-staging"; \
	rm -f "$$DMG_PATH"; \
	rm -rf "$$DMG_STAGING" 2>/dev/null || true; mkdir -p "$$DMG_STAGING"; \
	cp -R "dist/$(APP_NAME).app" "$$DMG_STAGING/"; \
	ln -s /Applications "$$DMG_STAGING/Applications"; \
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$$DMG_STAGING" -ov -format UDZO "$$DMG_PATH"; \
	rm -rf "$$DMG_STAGING"
	@echo "$(GREEN)==> DMG is at dist/$(APP_NAME)-macOS.dmg$(NC)"

clean: ## Remove all build products and dist
	@echo "$(YELLOW)==> Cleaning...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DIST_DIR)
	@echo "$(GREEN)==> Clean complete.$(NC)"

open: ## Restart + launch /Applications/GrokBuild.app
	@if [ ! -d "/Applications/$(APP_NAME).app" ]; then \
		echo "No app found at /Applications/$(APP_NAME).app. Run 'make install' first."; \
		exit 1; \
	fi
	@echo "$(GREEN)==> Starting $(APP_NAME)...$(NC)"
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.2
	@open "/Applications/$(APP_NAME).app"
	@echo "$(GREEN)==> $(APP_NAME) launched from /Applications/$(APP_NAME).app$(NC)"

# Convenience aliases
bundle: app
install: signed ## Copy .app to /Applications/ (codesigns when SIGN_IDENTITY is set in .env)
	@if [ ! -d "dist/$(APP_NAME).app" ]; then \
		echo "dist/$(APP_NAME).app not found. Run 'make app' first."; \
		exit 1; \
	fi
	@if [ ! -w /Applications ]; then \
		echo "Cannot write to /Applications. Try: sudo make install"; \
		exit 1; \
	fi
	@echo "$(GREEN)==> Installing to /Applications/$(APP_NAME).app...$(NC)"
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "dist/$(APP_NAME).app" /Applications/
	@if [ -z "$(SIGN_IDENTITY)" ]; then xattr -cr "/Applications/$(APP_NAME).app"; fi
	@if [ ! -f "/Applications/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" ]; then \
		echo "Install failed: /Applications/$(APP_NAME).app was not created."; \
		exit 1; \
	fi
	@echo "$(GREEN)==> Installed to /Applications/$(APP_NAME).app$(NC)"

# Packaging (SPM-based)
# The script handles creating the .app bundle + DMG and supports signing.

# Make 'signed' an alias for convenience
signed: app

# If someone runs `make app` with SIGN_IDENTITY, pass it through
app: ## Build the .app bundle (with icon). Signs when SIGN_IDENTITY is set in .env
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		./scripts/build-macos-app.sh --sign "$(SIGN_IDENTITY)"; \
	else \
		./scripts/build-macos-app.sh; \
	fi
	@echo "$(GREEN)==> .app ready in dist/$(APP_NAME).app$(NC)"

notarize: signed ## Notarize (builds + signs + notarizes). Set NOTARY_PROFILE=...
	@./scripts/notarize.sh
	@echo "$(GREEN)==> Notarization complete.$(NC)"

release: ## Publish GitHub release (RELEASE_TYPE/SIGN_IDENTITY/NOTARY_PROFILE from .env)
	@echo "==> Release: type=$(RELEASE_TYPE), sign=$$([ -n '$(SIGN_IDENTITY)' ] && echo yes || echo no), notary=$(NOTARY_PROFILE)"
	@./scripts/release.sh


# GrokDeck - Makefile for easy local macOS builds
#
# Uses SwiftPM (no Xcode project required).
# See BUILDING.md for full packaging & signing instructions.
#
# Usage:
#   make build          # Build Release binary with SwiftPM
#   make run            # Build + launch the menu bar app
#   make app            # Package .app into dist/
#   make dmg            # Package .app + DMG (auto-notarizes if NOTARY_PROFILE set)
#   make signed         # Codesigned build
#   make notarize       # Notarize (NOTARY_PROFILE=...)
#   make clean

APP_NAME       ?= GrokDeck
SCHEME         ?= GrokDeck
CONFIGURATION  ?= Release

DIST_DIR       ?= dist
BUILD_DIR      ?= .build

# Set this to your codesigning identity when using `make signed` or `make release`
# Example: make signed SIGN_IDENTITY="Developer ID Application: Rimas (ABC1234567)"
SIGN_IDENTITY  ?=

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
NC     := \033[0m

.PHONY: help build run app dmg signed clean open notarize

help: ## Show this help
	@echo "GrokDeck macOS Build Commands"
	@echo ""
	@echo "  $(YELLOW)make build$(NC)            Build release binary (SwiftPM)"
	@echo "  $(YELLOW)make run$(NC)             Build + launch the menu bar app"
	@echo "  $(YELLOW)make app$(NC)              Package .app into dist/"
	@echo "  $(YELLOW)make dmg$(NC)              Build .app + DMG (auto-notarizes + re-DMG if NOTARY_PROFILE set)"
	@echo "  $(YELLOW)make signed$(NC)           Codesigned release"
	@echo "  $(YELLOW)make notarize$(NC)         Notarize (NOTARY_PROFILE=...)"
	@echo "  $(YELLOW)make clean$(NC)            Remove build artifacts"
	@echo ""
	@echo "See BUILDING.md for full packaging & signing instructions."
	@echo ""
	@echo "Quick start: make run"
	@echo "Notarize example: make dmg NOTARY_PROFILE=AC_PASSWORD SIGN_IDENTITY=..."

build: ## Build using SwiftPM (Release) - recommended
	@echo "$(GREEN)==> Building $(APP_NAME) with SwiftPM (release)...$(NC)"
	@swift build -c release
	@chmod +x .build/release/GrokDeck 2>/dev/null || true
	@mkdir -p .build/release
	@cp -f GrokDeck/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png .build/release/ 2>/dev/null || true
	@cp -f GrokDeck/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png .build/release/ 2>/dev/null || true
	@cp -f GrokDeck/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png .build/release/ 2>/dev/null || true
	@cp -f AppIcon.png .build/release/ 2>/dev/null || true
	@echo "$(GREEN)==> Build complete. Use 'make run' to launch (or ./.build/release/GrokDeck directly).$(NC)"

run: build ## Build + launch the menu bar app
	@echo "$(GREEN)==> Starting GrokDeck...$(NC)"
	@./.build/release/GrokDeck > /dev/null 2>&1 & disown
	@echo "$(GREEN)==> GrokDeck launched.$(NC)"

dmg: ## Build the .app and package it into a DMG.
	@if [ -n "$(NOTARY_PROFILE)" ]; then \
		$(MAKE) notarize; \
		echo "$(GREEN)==> Re-creating DMG with stapled app...$(NC)"; \
		DMG_PATH="dist/$(APP_NAME)-macOS.dmg"; \
		rm -f "$$DMG_PATH"; \
		DMG_STAGING="dist/dmg-staging"; \
		rm -rf "$$DMG_STAGING" 2>/dev/null || true; mkdir -p "$$DMG_STAGING"; \
		cp -R "dist/$(APP_NAME).app" "$$DMG_STAGING/"; \
		ln -s /Applications "$$DMG_STAGING/Applications"; \
		hdiutil create -volname "$(APP_NAME)" -srcfolder "$$DMG_STAGING" -ov -format UDZO "$$DMG_PATH"; \
		rm -rf "$$DMG_STAGING"; \
	else \
		SIGN_OPTS=""; \
		if [ -n "$(SIGN_IDENTITY)" ]; then SIGN_OPTS="--sign \"$(SIGN_IDENTITY)\""; fi; \
		./scripts/build-macos-app.sh $$SIGN_OPTS; \
	fi
	@echo "$(GREEN)==> DMG is at dist/$(APP_NAME)-macOS.dmg$(NC)"

clean: ## Remove all build products and dist
	@echo "$(YELLOW)==> Cleaning...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DIST_DIR)
	@echo "$(GREEN)==> Clean complete.$(NC)"

open: ## Open the built app from dist/
	@if [ -d "dist/$(APP_NAME).app" ]; then \
		open "dist/$(APP_NAME).app"; \
	else \
		echo "No app found in dist/. Run 'make app' first."; \
		exit 1; \
	fi

# Convenience aliases
bundle: app
install: app
	@echo "Copying to /Applications (may require sudo)..."
	@cp -R "dist/$(APP_NAME).app" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

# Packaging (SPM-based)
# The script handles creating the .app bundle + DMG and supports signing.

# Make 'signed' an alias for convenience
signed: app

# If someone runs `make app` with SIGN_IDENTITY, pass it through
app: ## Build the .app bundle (with icon). Use SIGN_IDENTITY=... for codesigning
	@SCRIPT_OPTS=""; \
	if [ -n "$(SIGN_IDENTITY)" ]; then SCRIPT_OPTS="--sign \"$(SIGN_IDENTITY)\""; fi; \
	./scripts/build-macos-app.sh $$SCRIPT_OPTS
	# Icon copy is now handled inside the script
	@echo "$(GREEN)==> .app ready in dist/$(APP_NAME).app$(NC)"

NOTARY_PROFILE ?= AC_PASSWORD

notarize: signed ## Notarize (builds + signs + notarizes). Set NOTARY_PROFILE=...
	@./scripts/notarize.sh
	@echo "$(GREEN)==> Notarization complete.$(NC)"


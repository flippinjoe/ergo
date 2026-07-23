# Ergo — one interface for humans and agents.
#
# Common flow on a clean checkout:
#   make bootstrap && make test        # green package tests, no cluster
#   make generate && make build        # generate + build the macOS app
#
# Every target wraps a tool so the command surface stays identical whether a
# person or an agent runs it.

SHELL := /bin/bash
.DEFAULT_GOAL := help

XCODEGEN := swift run --package-path Tools xcodegen
PROJECT  := Ergo.xcodeproj
SCHEME   := Ergo
DEST     := platform=macOS
RESULTS  := TestResults

# swift-format ships with the toolchain; no install needed.
FORMAT_PATHS := Sources Tests App Package.swift Tools/Package.swift

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Verify the toolchain and build vendored tools (fails loudly if missing)
	@command -v swift >/dev/null 2>&1 || { echo "ERROR: swift not found. Install Xcode + command line tools."; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "ERROR: xcodebuild not found. Install Xcode."; exit 1; }
	@echo "Toolchain OK: $$(swift --version | head -1)"
	@echo "Building vendored XcodeGen (pinned in Tools/Package.swift)…"
	@swift build --package-path Tools --product xcodegen >/dev/null || { echo "ERROR: failed to build vendored XcodeGen."; exit 1; }
	@echo "Bootstrap complete."

.PHONY: generate
generate: ## Generate Ergo.xcodeproj from project.yml
	@$(XCODEGEN) generate --spec project.yml
	@echo "Generated $(PROJECT)."

.PHONY: build
build: ## Build the SPM package and the macOS app
	@echo "==> swift build (packages)"
	@swift build
	@echo "==> xcodebuild (app)"
	@test -d $(PROJECT) || $(MAKE) generate
	@set -o pipefail; xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		CODE_SIGNING_ALLOWED=NO | tail -20

.PHONY: test
test: ## Run the headless package test suite (machine-readable xunit output)
	@mkdir -p $(RESULTS)
	@swift test --xunit-output $(RESULTS)/xunit.xml
	@echo "xUnit results: $(RESULTS)/xunit.xml"

.PHONY: lint
lint: ## Lint with swift-format (enforced); run SwiftLint too if installed
	@echo "==> swift format lint --strict"
	@swift format lint --strict --recursive $(FORMAT_PATHS)
	@if command -v swiftlint >/dev/null 2>&1; then \
		echo "==> swiftlint"; swiftlint lint --quiet; \
	else \
		echo "note: swiftlint not installed — skipping (swift-format already enforced)."; \
	fi

.PHONY: format
format: ## Auto-format sources in place with swift-format
	@swift format format --in-place --recursive $(FORMAT_PATHS)
	@echo "Formatted."

.PHONY: run
run: build ## Build and launch the macOS app
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null \
		| awk '/ BUILT_PRODUCTS_DIR /{d=$$3} / FULL_PRODUCT_NAME /{n=$$3} END{print d"/"n}'); \
	echo "Launching $$APP"; open "$$APP"

.PHONY: ci
ci: bootstrap generate build test lint ## Full pipeline: bootstrap → generate → build → test → lint

.PHONY: clean
clean: ## Remove build artifacts and the generated project
	@rm -rf .build Tools/.build DerivedData $(RESULTS) $(PROJECT)
	@echo "Cleaned."

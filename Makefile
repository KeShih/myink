CONFIG ?= debug
INSTALL_DIR ?= $(HOME)/Applications
APP := $(INSTALL_DIR)/Myink.app

.PHONY: build test bundle install run run-fg logs lint format icon cert install-cli uninstall reset-tcc clean

build: ## Compile with SwiftPM
	swift build -c $(CONFIG)

test: ## Run the Swift Testing suites
	swift test

bundle: ## Build and assemble a signed build/Myink.app
	scripts/bundle.sh $(CONFIG)

install: bundle ## Install to ~/Applications and register with Launch Services (no launch)
	INSTALL_DIR="$(INSTALL_DIR)" scripts/install.sh --no-open

run: bundle ## Install and launch
	INSTALL_DIR="$(INSTALL_DIR)" scripts/install.sh

run-fg: install ## Install and run in the foreground (logs to the terminal)
	"$(APP)/Contents/MacOS/Myink"

logs: ## Stream Myink's unified logs
	/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "dev.keshi.myink"'

lint: ## SwiftLint + SwiftFormat checks (SourceKit can't load without Xcode, so SwiftLint runs without it)
	SWIFTLINT_DISABLE_SOURCEKIT=1 swiftlint lint --strict --quiet
	@! grep -rn 'Bundle\.module' Sources Tests || { echo "error: Bundle.module breaks code signing of Myink.app — use Bundle.main"; exit 1; }
	swiftformat --lint --quiet .

format: ## Apply SwiftFormat
	swiftformat --quiet .

icon: ## Re-render the app icon
	scripts/make-icon.sh --force

cert: ## Create the local self-signed signing identity (once)
	scripts/create-signing-cert.sh

install-cli: ## Symlink the `myink` CLI into ~/.local/bin
	mkdir -p "$(HOME)/.local/bin"
	ln -sf "$(APP)/Contents/Resources/myink" "$(HOME)/.local/bin/myink"
	@echo "myink CLI -> $(HOME)/.local/bin/myink"

uninstall: ## Remove the installed app (keeps shelf data)
	INSTALL_DIR="$(INSTALL_DIR)" scripts/uninstall.sh

reset-tcc: ## Reset Myink's privacy permissions
	tccutil reset All dev.keshi.myink

clean: ## Remove build products
	rm -rf .build build

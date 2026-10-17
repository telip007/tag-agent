# Backpressure for humans and agents: `make check` must pass before every push.
#
#   make bootstrap  install tools, enable git hooks, fetch the SDK submodule
#   make fix        auto-format
#   make check      lint + build (warnings are errors) + tests + coverage gate

SOURCES := Sources Package.swift $(wildcard Tests)
MIN_COVERAGE ?= 80

.PHONY: bootstrap fix format lint wiki-lint build test coverage check check-all sdk-check clean

bootstrap:
	@command -v swiftlint >/dev/null || brew install swiftlint
	git config core.hooksPath .githooks
	git submodule update --init --recursive

fix format:
	swift format format --in-place --recursive --parallel $(SOURCES)
	swiftlint lint --fix --quiet

lint: wiki-lint
	swift format lint --strict --recursive --parallel $(SOURCES)
	swiftlint lint --strict --quiet

wiki-lint:
	python3 -I Scripts/wiki-lint.py

build:
	swift build

# Tag has no test target yet; this starts enforcing as soon as Tests/ exists.
test:
ifneq ($(wildcard Tests),)
	swift test --parallel --enable-code-coverage
else
	@echo "test: no Tests/ directory yet, skipping"
endif

coverage: test
ifneq ($(wildcard Tests),)
	python3 -I Scripts/check-coverage.py "$$(swift test --show-codecov-path)" $(MIN_COVERAGE) Sources
endif

check: lint build coverage

# Also run the SDK's own checks.
sdk-check:
	$(MAKE) -C Packages/OpenRouter check

check-all: check sdk-check

clean:
	swift package clean

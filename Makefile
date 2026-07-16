.PHONY: app install test clean

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/swiftpm-module-cache

app: clean
	./scripts/package-app.sh

install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/QuotaPeek.app"
	cp -R "dist/QuotaPeek.app" "$(HOME)/Applications/QuotaPeek.app"
	open "$(HOME)/Applications/QuotaPeek.app"

test:
	swift test --disable-sandbox --scratch-path .build

clean:
	rm -rf .build dist

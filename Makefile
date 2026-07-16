.PHONY: app install test verify clean

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

verify:
	$(MAKE) test
	$(MAKE) app
	./scripts/verify-app.sh

clean:
	rm -rf .build .build-* dist

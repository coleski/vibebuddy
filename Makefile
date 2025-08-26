.PHONY: reset
reset:
	tccutil reset Accessibility com.kitlangton.Hex
	@echo "✅ Accessibility permissions reset for Hex"

.PHONY: build
build:
	xcodebuild -scheme Hex -configuration Release

.PHONY: test
test:
	xcodebuild test -scheme Hex

.PHONY: clean
clean:
	xcodebuild clean -scheme Hex
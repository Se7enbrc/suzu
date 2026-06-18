# suzu - a small, sandboxed macOS menu-bar audio companion.
#
# The Xcode project is generated from project.yml by XcodeGen, so the pbxproj
# never needs hand-editing. Version is single-sourced in Suzu/Version.xcconfig.
#
#   make build   - generate the project and compile (unsigned, fast check)
#   make app     - build a runnable, ad-hoc-signed .app
#   make run     - build and launch it
#   make test    - run the test bundle
#   make lint    - run SwiftLint
#   make clean   - remove build output and the generated project

APP_NAME := Suzu
PROJECT  := $(APP_NAME).xcodeproj
SCHEME   := $(APP_NAME)
CONFIG   ?= Debug
DERIVED  := build
PRODUCTS := $(DERIVED)/Build/Products/$(CONFIG)

.PHONY: all generate build app run test lint clean open

all: app

generate:
	xcodegen generate

# Compile only, no signing - the quick "does it build" gate.
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build

# Ad-hoc-signed build that actually runs the sandbox locally.
app: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) \
	  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES build

run: app
	open "$(PRODUCTS)/$(APP_NAME).app"

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -derivedDataPath $(DERIVED) test

lint:
	swiftlint

open: generate
	open $(PROJECT)

clean:
	rm -rf $(DERIVED) $(PROJECT)

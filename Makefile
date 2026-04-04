.PHONY: generate build run clean

generate:
	cd /Users/sonpiaz/pheme && xcodegen generate

open: generate
	open Pheme.xcodeproj

build: generate
	xcodebuild -project Pheme.xcodeproj -scheme Pheme -configuration Debug build

run: build
	open build/Debug/Pheme.app

clean:
	rm -rf build DerivedData .build
	rm -rf Pheme.xcodeproj

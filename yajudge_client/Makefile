DART=dart
FLUTTER=flutter
PUB=dart pub
RM=rm
UNAME:=$(shell uname -s)
PLATFORM=unknown
ifeq ($(UNAME), Darwin)
	PLATFORM=macos
endif
ifeq ($(UNAME), Linux)
	PLATFORM=linux
endif

first: all

all: web-client native-client

native-client: ${PLATFORM}
	$(FLUTTER) build ${PLATFORM}

macos: macos/Podfile.lock

macos/Podfile.lock:
	cd macos && pod install

web-client: deps
	$(FLUTTER) build web --release
	bash fix-issue-70101.sh

deps:
	$(FLUTTER) pub get


clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) .flutter* || true
	$(RM) pubspec.lock || true
	$(RM) macos/Podfile.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/*.exe || true
	$(RM) build/ || true



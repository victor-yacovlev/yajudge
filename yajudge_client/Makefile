FLUTTER=flutter
RM=rm
UNAME:=$(shell uname -s)
PLATFORM=unknown
ifeq ($(UNAME), Darwin)
	PLATFORM=macos
endif
ifeq ($(UNAME), Linux)
	PLATFORM=linux
endif

first: web

all: web native

native: ${PLATFORM}
	$(FLUTTER) build ${PLATFORM}

macos: macos/Podfile.lock

macos/Podfile.lock:
	cd macos && pod install

web: deps generated_code
	$(FLUTTER) build web

generated_code: deps
	$(FLUTTER) pub run build_runner build

deps:
	$(FLUTTER) pub get

clean:
	$(RM) lib/*/*.g.dart || true

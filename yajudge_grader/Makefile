DART=dart
RM=rm -rf
INSTALL=install
USERADD=useradd -rmU -s /usr/sbin/nologin
MAKEDIRS=mkdir -p
SYSTEMCTL=systemctl

PREFIX=/usr
ETC=/etc
USER=yajudge


first: all

all: grader

grader: bin/yajudge-grader
bin/yajudge-grader: .packages lib/src/generated/assets.gen.dart $(wildcard lib/src/*.dart) lib/grader_main.dart
	$(DART) compile exe -o bin/yajudge-grader bin/yajudge-grader.dart

deps: .packages
.packages:
	$(DART) pub get

gen: lib/src/generated/assets.gen.dart
lib/src/generated/assets.gen.dart: $(wildcard resources/*)
	$(DART) run lib/build_assets.dart


clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/yajudge-grader || true



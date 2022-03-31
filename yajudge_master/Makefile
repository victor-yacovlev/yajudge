DART=dart
RM=rm -rf
INSTALL=install
USERADD=useradd -rmU -s /usr/sbin/nologin
MAKEDIRS=mkdir -p

PREFIX=/usr
ETC=/etc
USER=yajudge


first: all

all: master

master: .packages gen bin/yajudge-master
bin/yajudge-master: bin/yajudge-master.dart lib/master_main.dart $(wildcard lib/src/*.dart)
	$(DART) compile exe -o bin/yajudge-master bin/yajudge-master.dart

gen: lib/src/generated/assets.gen.dart
lib/src/generated/assets.gen.dart: $(wildcard resources/*)
	$(DART) run lib/build_assets.dart

deps: .packages
.packages:
	$(DART) pub get


clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/yajudge-master || true



DART=dart
RM=rm -rf
INSTALL=install
PREFIX=/usr
ETC=/etc

first: all

all: grader

grader: bin/yajudge-grader
bin/yajudge-grader: .packages lib/src/generated/assets.gen.dart lib/grader_main.dart bin/yajudge-grader.dart $(find lib/src/*.dart -type f)
	$(DART) compile exe -o bin/yajudge-grader bin/yajudge-grader.dart

deps: .packages
.packages:
	$(DART) pub get

gen: lib/src/generated/assets.gen.dart
lib/src/generated/assets.gen.dart: resources/*
	$(DART) run lib/build_assets.dart

install: bin/yajudge-grader yajudge-grader.service conf/grader.yaml
	$(INSTALL) -D bin/yajudge-grader $(PREFIX)/bin/yajudge-grader
	$(INSTALL) -D yajudge-grader.service $(ETC)/systemd/system.control/yajudge-grader.service
	if [ -f $(ETC)/yajudge/grader.yaml ]
	then
		$(INSTALL) -D conf/grader.yaml $(ETC)/yajudge/grader.yaml.new
	else
		$(INSTALL) -D conf/grader.yaml $(ETC)/yajudge/grader.yaml
	fi

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/yajudge-grader || true



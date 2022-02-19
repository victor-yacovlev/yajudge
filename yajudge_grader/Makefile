DART=dart
RM=rm -rf
INSTALL=install
PREFIX=/usr
ETC=/etc

first: all

all: grader

grader: bin/yajudge-grader.exe
bin/yajudge-grader.exe: deps gen lib/grader_main.dart bin/yajudge-grader.dart lib/src/*.dart
	$(DART) compile exe bin/yajudge-grader.dart

deps: .packages
.packages:
	$(DART) pub get

gen: lib/src/generated/assets.gen.dart
lib/src/generated/assets.gen.dart: resources/*
	$(DART) run lib/build_assets.dart

install: grader
	$(INSTALL) -D bin/yajudge-grader.exe $(PREFIX)/bin/yajudge-grader
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
	$(RM) bin/*.exe || true



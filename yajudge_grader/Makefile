DART=dart
RM=rm -rf
INSTALL=install
PREFIX=/usr
ETC=/etc

first: all

all: grader helpers

grader: deps
	$(DART) compile exe bin/yajudge-grader.dart

helpers:


deps:
	$(DART) pub get

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



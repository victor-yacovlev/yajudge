DART=dart
RM=rm -rf

first: all

all: grader helpers

grader: deps
	$(DART) compile exe bin/yajudge-grader-server.dart
	$(DART) compile exe bin/yajudge-grader-tool.dart

helpers:


deps:
	$(DART) pub get

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/*.exe || true



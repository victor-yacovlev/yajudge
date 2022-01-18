DART=dart
RM=rm -rf

first: server

server: deps
	$(DART) compile exe bin/*.dart

deps:
	$(DART) pub get

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/*.exe || true



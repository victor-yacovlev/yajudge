DART=dart
RM=rm -rf

first: generated_code

generated_code: deps
	$(DART) run build_runner build

deps:
	$(DART) pub get
	$(DART) pub global activate protoc_plugin

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/*.exe || true
	$(RM) built.stamp || true



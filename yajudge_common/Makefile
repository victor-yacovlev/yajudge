DART=dart
RM=rm -rf
MAKEDIRS=mkdir -p
PROTOC=protoc

first: generated_code

generated_code: deps
	$(MAKEDIRS) lib/src/generated
	PATH=${HOME}/.pub-cache/bin/:${PATH} $(PROTOC) -I proto proto/yajudge.proto --dart_out=grpc:lib/src/generated

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



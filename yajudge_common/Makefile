DART=dart
RM=rm -rf
MAKEDIRS=mkdir -p
PROTOC=protoc
PROTOC_PLUGIN=$(HOME)/.pub-cache/bin/protoc-gen-dart

first: all

all: generated_code

generated_code: lib/src/generated/yajudge.pb.dart
lib/src/generated/yajudge.pb.dart: proto/yajudge.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge.proto --dart_out=grpc:lib/src/generated

deps: .packages protoc_plugin
.packages:
	$(DART) pub get

protoc_plugin: $(PROTOC_PLUGIN)
$(PROTOC_PLUGIN): .packages
	$(DART) pub global activate protoc_plugin

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/*.exe || true
	$(RM) built.stamp || true



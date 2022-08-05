DART=dart
RM=rm -rf
MAKEDIRS=mkdir -p
PROTOC=protoc
PROTOC_PLUGIN=$(HOME)/.pub-cache/bin/protoc-gen-dart

first: all

all: generated_code

generated_code: lib/src/generated/yajudge_common.pb.dart lib/src/generated/yajudge_users.pb.dart lib/src/generated/yajudge_courses.pb.dart lib/src/generated/yajudge_submissions.pb.dart lib/src/generated/yajudge_enrollments.pb.dart lib/src/generated/yajudge_code_reviews.pb.dart
lib/src/generated/yajudge_common.pb.dart: proto/yajudge_common.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge_common.proto --dart_out=grpc:lib/src/generated
lib/src/generated/yajudge_users.pb.dart: proto/yajudge_users.proto proto/yajudge_common.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge_users.proto --dart_out=grpc:lib/src/generated
lib/src/generated/yajudge_courses.pb.dart: proto/yajudge_courses.proto proto/yajudge_common.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge_courses.proto --dart_out=grpc:lib/src/generated
lib/src/generated/yajudge_submissions.pb.dart: proto/yajudge_submissions.proto proto/yajudge_common.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge_submissions.proto --dart_out=grpc:lib/src/generated
lib/src/generated/yajudge_enrollments.pb.dart: proto/yajudge_enrollments.proto proto/yajudge_common.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge_enrollments.proto --dart_out=grpc:lib/src/generated
lib/src/generated/yajudge_code_reviews.pb.dart: proto/yajudge_code_reviews.proto proto/yajudge_common.proto $(PROTOC_PLUGIN)
	$(MAKEDIRS) lib/src/generated
	PATH=$(HOME)/.pub-cache/bin/:$(PATH) $(PROTOC) -I proto proto/yajudge_code_reviews.proto --dart_out=grpc:lib/src/generated

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



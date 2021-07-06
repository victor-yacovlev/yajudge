# requires go version >= 1.16
GO=go

# reauires protoc that supports protocol version == 7 (e.g. protoc >= 1.5.0)
PROTOC=protoc

# can override to del for Windows
RM=rm

EXE_SUFFIX=

all: yajudge_server$(EXE_SUFFIX)

test: yajudge_server$(EXE_SUFFIX)
	$(GO) test -v -cover

protoc: core_service/service_grpc.pb.go core_service/service.pb.go

core_service/service_grpc.pb.go: service.proto
	$(PROTOC) --go-grpc_out=./core_service -I. service.proto

core_service/service.pb.go: service.proto
	$(PROTOC) --go_out=./core_service -I. service.proto

yajudge_server$(EXE_SUFFIX): main.go protoc
	$(GO) get yajudge/yajudge_server
	$(GO) build $(GOGLAGS) .

clean:
	$(RM) yajudge_server$(EXE_SUFFIX) || true
	$(RM) go.sum || true
	$(RM) */go.sum || true
	$(RM) */*.pb.go || true


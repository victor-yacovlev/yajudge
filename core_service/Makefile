# requires go version >= 1.16
GO=go

# reauires protoc that supports protocol version == 7 (e.g. protoc >= 1.5.0)
PROTOC=protoc

# can override to del for Windows
RM=rm

all: service

test: service
	$(GO) test -v -cover

service: go.sum service.go courses.go users.go service_grpc.pb.go service.pb.go
	$(GO) get yajudge/service
	$(GO) build $(GOGLAGS) .

go.sum: go.mod
	$(GO) mod download

service_grpc.pb.go: ../service.proto
	$(PROTOC) --go-grpc_out=. -I.. service.proto

service.pb.go: ../service.proto
	$(PROTOC) --go_out=. -I.. service.proto

clean:
	$(RM) *.pb.go || true
	$(RM) go.sum || true

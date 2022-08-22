PATH  := $(PATH):$(GOPATH)/bin

first: yajudge-server
all: yajudge-server

yajudge-server: $(wildcard *.go) deps
	go build -o yajudge-server

deps: go.sum protoc-gen-go protoc-gen-go-grpc

protoc-gen-go:
	go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28

protoc-gen-go-grpc:
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2

generate: yajudge_supervisor_grpc.pb.go
yajudge_supervisor_grpc.pb.go:
	go generate

clean:
	rm yajudge-server || true
	rm go.sum || true
	rm *.pb.go || true

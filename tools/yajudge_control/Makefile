PATH  := $(PATH):$(GOPATH)/bin

first: ../bin/yajudge-control

../bin/yajudge-control: $(wildcard *.go) deps generate yajudge_supervisor_grpc.pb.go
	go build -o ../bin/yajudge-control

deps: go.sum protoc-gen-go protoc-gen-go-grpc

protoc-gen-go:
	go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28

protoc-gen-go-grpc:
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2

go.sum: go.mod
	go get

generate: yajudge_supervisor_grpc.pb.go
yajudge_supervisor_grpc.pb.go:
	go generate


clean:
	rm ../bin/yajudge-control || true
	rm go.sum || true
	rm *.pb.go || true

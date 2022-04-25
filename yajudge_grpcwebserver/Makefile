first: yajudge-grpcwebserver
all: yajudge-grpcwebserver

yajudge-grpcwebserver: $(wildcard *.go) go.sum
	go build -o yajudge-grpcwebserver

deps: go.sum

go.sum: go.mod
	go get

clean:
	rm yajudge-grpcwebserver || true
	rm go.sum || true

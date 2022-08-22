first: yajudge-server
all: yajudge-server

yajudge-server: $(wildcard *.go) go.sum
	go build -o yajudge-server

deps: go.sum

go.sum: go.mod
	go get

clean:
	rm yajudge-server || true
	rm go.sum || true

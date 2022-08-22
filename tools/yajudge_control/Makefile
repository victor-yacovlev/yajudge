first: ../bin/yajudge-control

../bin/yajudge-control: $(wildcard *.go) go.sum
	go build -o ../bin/yajudge-control

deps: go.sum

go.sum: go.mod
	go get

clean:
	rm ../bin/yajudge-control || true
	rm go.sum || true

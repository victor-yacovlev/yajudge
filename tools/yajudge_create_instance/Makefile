first: ../bin/yajudge-create-instance

../bin/yajudge-create-instance: $(wildcard *.go) go.sum
	go build -o ../bin/yajudge-create-instance

go.sum: go.mod
	go get

clean:
	rm ../bin/yajudge-create-instance || true
	rm go.sum || true

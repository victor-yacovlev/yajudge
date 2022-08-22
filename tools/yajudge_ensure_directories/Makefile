first: ../bin/yajudge-ensure-directories

../bin/yajudge-ensure-directories: $(wildcard *.go) go.sum
	go build -o ../bin/yajudge-ensure-directories

go.sum: go.mod
	go get

clean:
	rm ../bin/yajudge-ensure-directories || true
	rm go.sum || true

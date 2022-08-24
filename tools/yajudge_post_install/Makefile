first: ../bin/yajudge-post-install

../bin/yajudge-post-install: $(wildcard *.go) go.sum
	go build -o ../bin/yajudge-post-install

go.sum: go.mod
	go get

clean:
	rm ../bin/yajudge-post-install || true
	rm go.sum || true

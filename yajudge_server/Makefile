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

yajudge_server$(EXE_SUFFIX): go.sum main.go
	$(GO) get yajudge/yajudge_server
	$(GO) build $(GOGLAGS) .

go.sum: go.mod
	$(GO) mod download

clean:
	$(RM) yajudge_server$(EXE_SUFFIX) || true
	$(RM) go.sum || true

all: yajudge_server

yajudge_server:
	cd yajudge_server && make all

clean:
	cd yajudge_server && make clean

test:
	cd yajudge_server && make test

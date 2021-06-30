all: backend

backend:
	cd yajudge_server && make all

clean:
	cd core_service && make clean
	cd ws_service && make clean
	cd yajudge_server && make clean

test:
	cd core_service && make test
	cd ws_service && make test
	cd yajudge_server && make test

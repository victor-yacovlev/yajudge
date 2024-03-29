RELEASE_VER=$(shell date '+%y.%m.%d')
ARCH=$(shell uname -m)
OS=$(shell uname -s | tr '[:upper:]' '[:lower:]')
TGZ_DIR=yajudge-$(OS)-$(ARCH)
TGZ_FILE=yajudge-$(RELEASE_VER)-$(OS)-$(ARCH).tgz
GOPATH=$(HOME)/go

first: server_files

server_files:
	make -C yajudge_common
	make -C yajudge_master_services
	make -C yajudge_grader
	make -C yajudge_grpcwebserver
	make -C yajudge_client web-client
	make -C yajudge_server
	make -C tools

clean:
	make -C yajudge_common clean
	make -C yajudge_master_services clean
	make -C yajudge_grader clean
	make -C yajudge_grpcwebserver clean
	make -C yajudge_client clean
	make -C yajudge_server clean
	make -C tools clean

tgz_bundle: server_files
	mkdir -m 0775 -p $(TGZ_DIR)/bin
	mkdir -m 0775 -p $(TGZ_DIR)/web
	mkdir -m 0775 -p $(TGZ_DIR)/conf
	mkdir -m 0775 -p $(TGZ_DIR)/systemd 
	cp yajudge_master_services/bin/yajudge-service-* $(TGZ_DIR)/bin
	cp yajudge_grader/bin/yajudge-grader $(TGZ_DIR)/bin
	cp yajudge_grpcwebserver/yajudge-grpcwebserver $(TGZ_DIR)/bin
	cp yajudge_server/yajudge-server $(TGZ_DIR)/bin
	cp -R yajudge_client/build/web $(TGZ_DIR)
	cp tools/bin/* $(TGZ_DIR)/bin
	cp yajudge_master_services/conf/*.yaml $(TGZ_DIR)/conf
	cp yajudge_grader/conf/grader@.in.yaml $(TGZ_DIR)/conf
	cp yajudge_grpcwebserver/webserver.in.yaml $(TGZ_DIR)/conf
	cp yajudge_grpcwebserver/nginx@.in.conf $(TGZ_DIR)/conf
	cp yajudge_grpcwebserver/web@.in.yaml $(TGZ_DIR)/conf
	cp yajudge_server/supervisor@.in.yaml $(TGZ_DIR)/conf
	cp yajudge_server/yajudge.slice $(TGZ_DIR)/systemd
	cp yajudge_server/server.yaml $(TGZ_DIR)/conf
	cp yajudge_server/yajudge.in.service $(TGZ_DIR)/systemd
	cp bundle_README.md $(TGZ_DIR)/README.md
	cp LICENSE $(TGZ_DIR)
	echo $(RELEASE_VER) > $(TGZ_DIR)/VERSION
	tar cfvz $(TGZ_FILE) $(TGZ_DIR)

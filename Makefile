RELEASE_VER=$(shell date '+%y.%m.%d')
ARCH=$(shell uname -m)
OS=$(shell uname -s | tr '[:upper:]' '[:lower:]')
TGZ_DIR=yajudge-$(OS)-$(ARCH)
TGZ_FILE=yajudge-$(RELEASE_VER)-$(OS)-$(ARCH).tgz
GOPATH=$(HOME)/go
GRPCWEBPROXY=$(GOPATH)/bin/grpcwebproxy

first: servers

servers:
	make -C yajudge_common
	make -C yajudge_master
	make -C yajudge_grader
	make -C yajudge_grpcwebserver
	make -C yajudge_client web-client

clean:
	make -C yajudge_common clean
	make -C yajudge_master clean
	make -C yajudge_grader clean
	make -C yajudge_grpcwebserver clean
	make -C yajudge_client clean

tgz_bundle: servers
	mkdir -p $(TGZ_DIR)/bin
	mkdir -p $(TGZ_DIR)/web
	mkdir -p $(TGZ_DIR)/conf
	mkdir -p $(TGZ_DIR)/systemd
	cp yajudge_master/bin/yajudge-master $(TGZ_DIR)/bin
	cp yajudge_grader/bin/yajudge-grader $(TGZ_DIR)/bin
	cp yajudge_grpcwebserver/yajudge-grpcwebserver $(TGZ_DIR)/bin
	cp -R yajudge_client/build/web $(TGZ_DIR)
	cp yajudge_master/conf/master.in.yaml $(TGZ_DIR)/conf
	cp yajudge_grader/conf/grader.in.yaml $(TGZ_DIR)/conf
	cp yajudge_grpcwebserver/conf/grpcwebserver.in.yaml $(TGZ_DIR)/conf
	cp yajudge_grpcwebserver/conf/nginx@.in.conf $(TGZ_DIR)/conf
	cp yajudge_grpcwebserver/conf/site@.in.yaml $(TGZ_DIR)/conf
	cp yajudge_master/yajudge-master@.in.service $(TGZ_DIR)/systemd
	cp yajudge_grader/yajudge-grader@.in.service $(TGZ_DIR)/systemd
	cp yajudge_grader/yajudge-grader-prepare.in.service $(TGZ_DIR)/systemd
	cp yajudge_grader/yajudge-grader.slice $(TGZ_DIR)/systemd
	cp yajudge_grpcwebserver/yajudge-grpcwebserver.in.service $(TGZ_DIR)/systemd
	cp bundle_README.md $(TGZ_DIR)/README.md
	cp bundle_post_install.sh $(TGZ_DIR)/post_install.sh
	cp LICENSE $(TGZ_DIR)
	echo $(RELEASE_VER) > $(TGZ_DIR)/VERSION
	tar cfvz $(TGZ_FILE) $(TGZ_DIR)


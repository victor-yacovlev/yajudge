DART=dart
RM=rm -rf
INSTALL=install
USERADD=useradd -rmU -s /usr/sbin/nologin
MAKEDIRS=mkdir -p

PREFIX=/usr
ETC=/etc
USER=yajudge


first: all

all: master

master: .packages bin/yajudge-master lib/src/generated/assets.gen.dart
bin/yajudge-master: bin/yajudge-master.dart lib/master_main.dart $(wildcard lib/src/*.dart)
	$(DART) compile exe -o bin/yajudge-master bin/yajudge-master.dart

gen: lib/src/generated/assets.gen.dart
lib/src/generated/assets.gen.dart: $(wildcard resources/*)
	$(DART) run lib/build_assets.dart

deps: .packages
.packages:
	$(DART) pub get

install: bin/yajudge-master yajudge-master@.service yajudge-envoy@.service conf/master.yaml conf/envoy.yaml
	$(INSTALL) -D bin/yajudge-master $(PREFIX)/bin/yajudge-master
	$(INSTALL) -D -m 0644 yajudge-master@.service $(ETC)/systemd/system/yajudge-master@.service
	$(INSTALL) -D -m 0644 yajudge-envoy@.service $(ETC)/systemd/system/yajudge-envoy@.service
	ln -f -s -T yajudge-master@.service $(ETC)/systemd/system/yajudge-master@default.service
	ln -f -s -T yajudge-envoy@.service $(ETC)/systemd/system/yajudge-envoy@default.service
	systemctl daemon-reload
	if [ -f $(ETC)/yajudge/master-default.yaml ]; then $(INSTALL) -m 0644 -D conf/master.yaml $(ETC)/yajudge/master-default.yaml.new; else $(INSTALL) -D -m 0644 conf/master.yaml $(ETC)/yajudge/master-default.yaml; fi
	if [ -f $(ETC)/yajudge/envoy-default.yaml ]; then $(INSTALL) -m 0644 -D conf/envoy.yaml $(ETC)/yajudge/envoy-default.yaml.new; else $(INSTALL) -D -m 0644 conf/envoy.yaml $(ETC)/yajudge/envoy-default.yaml; fi
	if [ ! -d /var/log/yajudge ]; then $(MAKEDIRS) /var/log/yajudge; fi
	chown $(USER):$(USER) /var/log/yajudge
	chmod 0770 /var/log/yajudge
	if [ ! -d /run/yajudge ]; then $(MAKEDIRS) /run/yajudge; fi
	chown $(USER):$(USER) /run/yajudge
	chmod 0770 /run/yajudge
	if [ ! -d /var/lib/yajudge ]; then $(MAKEDIRS) /var/lib/yajudge; fi
	chown $(USER):$(USER) /var/lib/yajudge
	chmod 0770 /var/lib/yajudge/
	touch $(ETC)/yajudge/private-token.txt
	chown $(USER):$(USER) $(ETC)/yajudge/private-token.txt
	chmod 0440 $(ETC)/yajudge/private-token.txt
	touch $(ETC)/yajudge/database-password.txt
	chown $(USER):$(USER) $(ETC)/yajudge/database-password.txt
	chmod 0440 $(ETC)/yajudge/database-password.txt
	if [ -f $(ETC)/nginx/sites-available/yajudge.conf ]; then $(INSTALL) -m 0644 -D conf/nginx.conf $(ETC)/nginx/sites-available/yajudge.conf.new; else $(INSTALL) -D -m 0644 conf/nginx.conf $(ETC)/nginx/sites-available/yajudge.conf; fi

user:
	if [ ! `id -u $(USER)` ]; then $(USERADD) -d /var/lib/$(USER) $(USER); fi

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/yajudge-master || true



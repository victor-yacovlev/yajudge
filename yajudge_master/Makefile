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

master: .packages bin/yajudge-master
bin/yajudge-master: bin/yajudge-master.dart lib/master_main.dart $(wildcard lib/src/*.dart)
	$(DART) compile exe -o bin/yajudge-master bin/yajudge-master.dart

deps: .packages
.packages:
	$(DART) pub get

install: bin/yajudge-master yajudge-master.service conf/master.yaml
	$(INSTALL) -D bin/yajudge-master $(PREFIX)/bin/yajudge-master
	$(INSTALL) -D -m 0644 yajudge-master.service $(ETC)/systemd/system/yajudge-master.service
	if [ -f $(ETC)/yajudge/master.yaml ]; then $(INSTALL) -m 0644 -D conf/master.yaml $(ETC)/yajudge/master.yaml.new; else $(INSTALL) -D -m 0644 conf/master.yaml $(ETC)/yajudge/master.yaml; fi
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
	chmod 0660 $(ETC)/yajudge/private-token.txt

user:
	if [ ! `id -u $(USER)` ]; then $(USERADD) -d /var/lib/$(USER) $(USER); fi

clean:
	$(RM) .dart_tool || true
	$(RM) .packages || true
	$(RM) pubspec.lock || true
	$(RM) lib/src/generated || true
	$(RM) bin/yajudge-master || true



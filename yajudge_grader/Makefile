DART=dart
RM=rm -rf
INSTALL=install
USERADD=useradd -rmU -s /usr/sbin/nologin
MAKEDIRS=mkdir -p
SYSTEMCTL=systemctl

PREFIX=/usr
ETC=/etc
USER=yajudge


first: all

all: grader

grader: bin/yajudge-grader
bin/yajudge-grader: .packages lib/src/generated/assets.gen.dart $(wildcard lib/src/*.dart) lib/grader_main.dart
	$(DART) compile exe -o bin/yajudge-grader bin/yajudge-grader.dart

deps: .packages
.packages:
	$(DART) pub get

gen: lib/src/generated/assets.gen.dart
lib/src/generated/assets.gen.dart: $(wildcard resources/*)
	$(DART) run lib/build_assets.dart

install: bin/yajudge-grader yajudge-grader@.service yajudge-grader-prepare.service yajudge-grader.slice conf/grader.yaml
	$(INSTALL) -D bin/yajudge-grader $(PREFIX)/bin/yajudge-grader
	$(INSTALL) -D -m 0644 yajudge-grader@.service $(ETC)/systemd/system/yajudge-grader@.service
	ln -f -s -T yajudge-grader@.service $(ETC)/systemd/system/yajudge-grader@default.service
	$(INSTALL) -D -m 0644 yajudge-grader.slice $(ETC)/systemd/system/yajudge-grader.slice
	$(INSTALL) -D -m 0644 yajudge-grader-prepare.service $(ETC)/systemd/system/yajudge-grader-prepare.service
	$(SYSTEMCTL) daemon-reload
	if [ -f $(ETC)/yajudge/grader.yaml ]; then $(INSTALL) -m 0644 -D conf/grader.yaml $(ETC)/yajudge/grader.yaml.new; else $(INSTALL) -D -m 0644 conf/grader.yaml $(ETC)/yajudge/grader.yaml; fi
	if [ ! -d /var/log/yajudge ]; then $(MAKEDIRS) /var/log/yajudge; fi
	chown $(USER):$(USER) /var/log/yajudge
	chmod 0770 /var/log/yajudge
	if [ ! -d /run/yajudge ]; then $(MAKEDIRS) /run/yajudge; fi
	chown $(USER):$(USER) /run/yajudge
	chmod 0770 /run/yajudge
	if [ ! -d /var/cache/yajudge ]; then $(MAKEDIRS) /var/cache/yajudge; fi
	chown $(USER):$(USER) /var/cache/yajudge
	chmod 0770 /var/cache/yajudge/
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
	$(RM) bin/yajudge-grader || true



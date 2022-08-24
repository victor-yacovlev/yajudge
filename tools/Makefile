first: all

all: control ensure-directories post-install

control:
	make -C yajudge_control

ensure-directories:
	make -C yajudge_ensure_directories

post-install:
	make -C yajudge_post_install

clean:
	make -C yajudge_control clean
	make -C yajudge_ensure_directories clean
	make -C yajudge_post_install clean
	rm -rf bin

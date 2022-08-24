first: all

all: control ensure-directories post-install create-instance

control:
	make -C yajudge_control

ensure-directories:
	make -C yajudge_ensure_directories

post-install:
	make -C yajudge_post_install

create-instance:
	make -C yajudge_create_instance

clean:
	make -C yajudge_control clean
	make -C yajudge_ensure_directories clean
	make -C yajudge_post_install clean
	make -C yajudge_create_instance clean
	rm -rf bin

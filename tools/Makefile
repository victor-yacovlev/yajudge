first: all

all: control ensure-directories

control:
	make -C yajudge_control

ensure-directories:
	make -C yajudge_ensure_directories

clean:
	make -C yajudge_control clean
	make -C yajudge_ensure_directories clean
	rm -rf bin

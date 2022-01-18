first: all

all: master grader web-client native-client

master: yajudge_common/built.stamp
	make -C yajudge_master

grader: yajudge_common/built.stamp
	make -C yajudge_grader

web-client: yajudge_common/built.stamp
	make -C yajudge_client web-client

native-client: yajudge_common/built.stamp
	make -C yajudge_client native-client

yajudge_common/built.stamp:
	make -C yajudge_common && touch yajudge_common/built.stamp

clean:
	make -C yajudge_common clean
	make -C yajudge_master clean
	make -C yajudge_grader clean
	make -C yajudge_client clean

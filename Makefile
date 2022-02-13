first: servers

servers:
	make -C yajudge_common
	make -C yajudge_master
	make -C yajudge_grader
	make -C yajudge_client web-client

clean:
	make -C yajudge_common clean
	make -C yajudge_master clean
	make -C yajudge_grader clean
	make -C yajudge_client clean

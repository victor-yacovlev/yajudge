module grader_service

go 1.16

replace (
	yajudge/service => ../../yajudge_server/core_service
)

require (
	gopkg.in/yaml.v2 v2.4.0
	google.golang.org/grpc v1.38.0
	yajudge/service v0.0.0-00010101000000-000000000000
)

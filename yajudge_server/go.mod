module yajudge/yajudge_server

go 1.16

replace (
	yajudge/service => ./core_service
	yajudge/ws_service => ./ws_service
)

require (
	gopkg.in/yaml.v2 v2.4.0
	yajudge/service v0.0.0-00010101000000-000000000000
	yajudge/ws_service v0.0.0-00010101000000-000000000000
)

module yajudge/ws_service

go 1.16

replace (
	yajudge/service => ../core_service
)

require (
	github.com/gorilla/websocket v1.4.2
	google.golang.org/grpc v1.38.0
	yajudge/service v0.0.0-00010101000000-000000000000
)

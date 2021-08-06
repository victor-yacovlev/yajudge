module yajudge_server

go 1.16

//replace (
//	yajudge/service => ./core_service
//	yajudge/ws_service => ./ws_service
//)

//replace yajudge_server => ./

require (
	github.com/gorilla/websocket v1.4.2
	github.com/lib/pq v1.10.2
	google.golang.org/grpc v1.39.1
	google.golang.org/protobuf v1.27.1
	gopkg.in/yaml.v2 v2.4.0
)

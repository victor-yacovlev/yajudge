module yajudge_grader

go 1.16

//grader_service => ./grader_service
//checkers => ./checkers
replace yajudge_server => ../yajudge_server

require (
	google.golang.org/grpc v1.39.1
	gopkg.in/yaml.v2 v2.4.0
	yajudge_server v0.0.0-00010101000000-000000000000
//grader_service v0.0.0-00010101000000-000000000000
//yajudge_server v0.0.0-00010101000000-000000000000
//yajudge_grader v0.0.0-00010101000000-000000000000
)

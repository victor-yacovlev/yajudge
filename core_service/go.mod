module yajudge/service

go 1.16

replace (
	yajudge/service => ./
)

require (
	golang.org/x/net v0.0.0-20210614182718-04defd469f4e // indirect
	google.golang.org/genproto v0.0.0-20210617175327-b9e0b3197ced // indirect
	google.golang.org/grpc v1.38.0
	google.golang.org/protobuf v1.26.0
	github.com/lib/pq v1.10.2
)

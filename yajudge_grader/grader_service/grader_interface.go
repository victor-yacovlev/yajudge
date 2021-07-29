package grader_service

import (
	yajudge "yajudge/service"
)

type GraderInterface interface {
	// Assumptions for all methods: all files was created before in `rootDir`

	CheckStyle(rootDir string, style *yajudge.CodeStyle, solution *yajudge.File) (ok bool, report string, err error)
	Compile(rootDir string, style *yajudge.GradingOptions, solution *yajudge.FileSet) (ok bool, report string, err error)
}
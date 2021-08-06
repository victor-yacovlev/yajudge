package grader_service

import (
	yajudge "yajudge_server/core_service"
)

type GraderInterface interface {
	// Assumptions for all methods: all files was created before in `rootDir`

	GetName() string
	GetArch() yajudge.Arch
	GetOs() yajudge.OS
	GetSupportedRuntimes() []string

	CheckStyle(rootDir string, solution *yajudge.File) (ok bool, failedName string, err error)
	BuildTarget(rootDir string, target *yajudge.GradingTarget) (ok bool, report string, err error)
	RunTarget(rootDir string, rt *yajudge.GradingRuntime, target *yajudge.GradingTarget,
		testNumber int, testCase *yajudge.TestCase,
		limits *yajudge.GradingLimits) (ok bool, status int, stdout, stderr []byte, err error)
}

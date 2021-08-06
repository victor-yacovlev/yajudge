package grader_service

import (
	"context"
	"fmt"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"os"
	"runtime"
	"strconv"
	"strings"
	"yajudge_grader/checkers"
	. "yajudge_server/core_service"
)

type RpcConfig struct {
	Host         string `yaml:"host"`
	Port         uint16 `yaml:"port"`
	PublicToken  string `yaml:"public_token"`
	PrivateToken string `yaml:"private_token"`
}

type GraderCourseDataCacheItem struct {
	Timestamp  int64
	CourseData *CourseData
}

type GraderService struct {
	SubmissionsProvider SubmissionManagementClient
	CoursesProvider     CourseManagementClient
	ContextMetadata     metadata.MD

	CourseDataCache  map[string]GraderCourseDataCacheItem
	WorkingDirectory string

	Worker GraderInterface
}

func NewGraderService() *GraderService {
	return &GraderService{
		CourseDataCache: make(map[string]GraderCourseDataCacheItem),
	}
}

func (service *GraderService) ConnectToMasterService(config RpcConfig) (err error) {
	grpcAddr := config.Host + ":" + strconv.Itoa(int(config.Port))
	grpcConn, err := grpc.Dial(grpcAddr, grpc.WithInsecure())
	if err != nil {
		return err
	}
	submissionManager := NewSubmissionManagementClient(grpcConn)
	coursesManager := NewCourseManagementClient(grpcConn)
	service.SubmissionsProvider = submissionManager
	service.CoursesProvider = coursesManager
	service.ContextMetadata = metadata.Pairs("auth", config.PrivateToken)
	return nil
}

func (service *GraderService) LoadCourseData(course *Course) (result *CourseData, err error) {
	var cachedTimestamp int64 = 0
	var cachedCourseData *CourseData = nil
	courseDataId := course.DataId
	if cacheContent, inCache := service.CourseDataCache[courseDataId]; inCache {
		cachedTimestamp = cacheContent.Timestamp
		cachedCourseData = cacheContent.CourseData
	}
	ctx := metadata.NewOutgoingContext(context.Background(), service.ContextMetadata)
	maxSizeOption := grpc.MaxCallRecvMsgSize(1024 * 1024 * 1024)
	contentResponse, err := service.CoursesProvider.GetCourseFullContent(ctx,
		&CourseContentRequest{
			CourseDataId:    courseDataId,
			CachedTimestamp: cachedTimestamp,
		},
		maxSizeOption,
	)
	if err != nil {
		return nil, err
	}
	if contentResponse.Status == CourseContentStatus_HAS_DATA {
		service.CourseDataCache[courseDataId] = GraderCourseDataCacheItem{
			CourseData: contentResponse.Data,
			Timestamp:  contentResponse.LastModified,
		}
		return contentResponse.Data, nil
	} else {
		return cachedCourseData, nil
	}
}

func FindProblemData(course *CourseData, problemId string) (result *ProblemData) {
	for _, section := range course.Sections {
		for _, lesson := range section.Lessons {
			for _, problem := range lesson.Problems {
				if problem.Id == problemId {
					return problem
				}
			}
		}
	}
	return nil
}

func CreateFileWithPath(name string, data []byte) (err error) {
	lastSlash := strings.LastIndex(name, string(os.PathSeparator))
	dirName := name[0:lastSlash]
	if dirName != "" {
		err = os.MkdirAll(dirName, 0777)
		if err != nil {
			return fmt.Errorf("can't create '%s': %v", dirName, err)
		}
	}
	err = os.WriteFile(name, data, 0666)
	if err != nil {
		return fmt.Errorf("can't create '%s': %v", name, err)
	}
	return nil
}

func ExtractFileset(root string, fileset *FileSet) (err error) {
	if fileset == nil || fileset.Files == nil {
		return nil
	}
	for _, file := range fileset.Files {
		fileName := root + string(os.PathSeparator) + file.Name
		if err = CreateFileWithPath(fileName, file.Data); err != nil {
			return err
		}
	}
	return nil
}

func (service *GraderService) processSubmission(submission *Submission) (result *Submission, err error) {
	courseData, err := service.LoadCourseData(submission.Course)
	if err != nil {
		return nil, fmt.Errorf("can't load course '%s' data: %v", submission.Course.DataId, err)
	}
	problem := FindProblemData(courseData, submission.ProblemId)
	if problem == nil {
		return nil, fmt.Errorf("no problem '%s' in course '%s'", submission.ProblemId, courseData.Id)
	}

	// 1. Create submission directory and save all files
	problemRoot := service.WorkingDirectory + string(os.PathSeparator) + strconv.Itoa(int(submission.Id))
	solution := submission.SolutionFiles

	for _, style := range courseData.CodeStyles {
		file := style.StyleFile
		styleFileName := problemRoot + string(os.PathSeparator) + file.Name
		if err = CreateFileWithPath(styleFileName, file.Data); err != nil {
			return nil, err
		}
	}
	if err = ExtractFileset(problemRoot, problem.GraderFiles); err != nil {
		return nil, err
	}
	if err = ExtractFileset(problemRoot, solution); err != nil {
		return nil, err
	}

	// 2. Check code style
	styleCheckFailed := false
	styleCheckError := ""
	for _, file := range solution.Files {
		for _, style := range courseData.CodeStyles {
			if strings.HasSuffix(file.Name, style.SourceFileSuffix) {
				ok, failedFileName, err := service.Worker.CheckStyle(problemRoot, file)
				if err != nil {
					return nil, fmt.Errorf("can't run style check for id '%d': %v", submission.Id, err)
				}
				if !ok {
					styleCheckFailed = true
					if styleCheckError != "" {
						styleCheckError += " "
					}
					styleCheckError = failedFileName
					break
				}
			}
		}
	}
	if styleCheckFailed {
		submission.StyleFailedName = styleCheckError
		submission.Status = SolutionStatus_STYLE_CHECK_ERROR
		return submission, nil
	}

	// 3. Build solution targets
	if problem.GradingOptions == nil {
		problem.GradingOptions = &GradingOptions{Targets: make([]*GradingTarget, 0, 1)}
	}
	if problem.GradingOptions.Runtimes == nil || len(problem.GradingOptions.Runtimes) == 0 {
		problem.GradingOptions.Runtimes = make([]*GradingRuntime, 0, 1)
		problem.GradingOptions.Runtimes = append(problem.GradingOptions.Runtimes, &GradingRuntime{
			Name: "default",
		})
	}
	if problem.GradingOptions.Targets == nil || len(problem.GradingOptions.Targets) == 0 {
		// generate targets from runtimes
		problem.GradingOptions.Targets = make([]*GradingTarget, 0, len(problem.GradingOptions.Runtimes))
		for _, rt := range problem.GradingOptions.Runtimes {
			target := &GradingTarget{}
			service.GenerateDefaultTargetBuildScripts(rt, target, solution, problem.GradingOptions.ExtraCompileOptions, problem.GradingOptions.ExtraLinkOptions)
			problem.GradingOptions.Targets = append(problem.GradingOptions.Targets, target)
		}
	}
	for _, target := range problem.GradingOptions.Targets {
		compileOk, compileReport, err := service.Worker.BuildTarget(problemRoot, target)
		if err != nil {
			return nil, err
		}
		if !compileOk {
			submission.BuildErrors = compileReport
			submission.Status = SolutionStatus_COMPILATION_ERROR
			return submission, nil
		}
	}

	// 4. Run test cases for all targets
	testsFailed := 0
	testsPassed := 0
	submission.TestResult = make([]*TestResult, 0, len(problem.GradingOptions.Runtimes)*len(problem.GradingOptions.TestCases))
	var checker checkers.CheckerInterface
	if problem.GradingOptions.StandardChecker != "" {
		checker = checkers.StandardCheckerByName(problem.GradingOptions.StandardChecker)
		if checker == nil {
			return nil, fmt.Errorf("not valid checker %s", problem.GradingOptions.StandardChecker)
		}
	}
	for runtimeIndex := 0; runtimeIndex < len(problem.GradingOptions.Runtimes); runtimeIndex++ {
		target := problem.GradingOptions.Targets[runtimeIndex]
		rt := problem.GradingOptions.Runtimes[runtimeIndex]
		rtName := rt.Name
		osName := runtime.GOOS
		if osName == "darwin" {
			// MacOS has no all Linux tools ported
			if rtName == "qemu-arm" || rtName == "valgrind" {
				continue
			}
		}
		limits := problem.GradingOptions.Limits
		for testIndex, testCase := range problem.GradingOptions.TestCases {
			testNumber := testIndex + 1
			testResult := &TestResult{
				Target:     rtName,
				TestNumber: int32(testNumber),
			}
			ok, status, stdout, stderr, err := service.Worker.RunTarget(problemRoot, rt, target, testNumber, testCase, limits)
			if err != nil {
				return nil, fmt.Errorf("can't run test %d for runtime %s: %v",
					testNumber, rt.Name, err)
			}
			resultMatch := checker.Match(stdout, testCase.StdoutReference.Data)
			if !ok || !resultMatch {
				testsFailed += 1
			} else {
				testsPassed += 1
			}
			testResult.Exited = ok
			testResult.Status = int32(status)
			testResult.Stdout = string(stdout)
			testResult.Stderr = string(stderr)
			testResult.StandardMatch = resultMatch
			submission.TestResult = append(submission.TestResult, testResult)
		}
	}
	if testsFailed == 0 {
		submission.Status = SolutionStatus_PENDING_REVIEW
	} else {
		submission.Status = SolutionStatus_VERY_BAD
	}
	return submission, nil
}

func (service *GraderService) GenerateDefaultTargetBuildScripts(
	rt *GradingRuntime,
	target *GradingTarget,
	solution *FileSet,
	extraCompileOptions []string,
	extraLinkOptions []string,
) {
	if target.TargetFileName == "" {
		target.TargetFileName = "build_" + rt.Name
	}
	filesToLink := make([]string, 0, len(solution.Files))
	target.BuildCommands = make([]string, 0, len(solution.Files)+1)
	hasGoFiles := false
	linkStdCxx := false
	for _, file := range solution.Files {
		fileSuffix := service.GetFileSuffix(file.Name)
		switch fileSuffix {
		case ".c", ".cpp", ".cxx", ".cc", ".S":
			objectFileName := file.Name + "." + rt.Name + ".o"
			command := service.DefaultGCCCompileCommand(rt.Name, file.Name, extraCompileOptions)
			target.BuildCommands = append(target.BuildCommands, command)
			filesToLink = append(filesToLink, objectFileName)
			linkStdCxx = fileSuffix == ".cpp" || fileSuffix == ".cxx" || fileSuffix == ".cc"
		case ".go":
			hasGoFiles = true
		}
	}
	if hasGoFiles {
		target.BuildCommands = append(target.BuildCommands, "go generate", "go get")
	}
	if len(filesToLink) > 0 || hasGoFiles {
		if !strings.HasSuffix(target.TargetFileName, ".exe") &&
			(runtime.GOOS == "windows" || rt.Name == "wine") {
			target.TargetFileName += ".exe"
		}
	}
	if len(filesToLink) > 0 {
		command := service.DefaultGCCLinkCommand(rt.Name, target.TargetFileName, filesToLink, linkStdCxx, extraLinkOptions)
		target.BuildCommands = append(target.BuildCommands, command)
	}
	if hasGoFiles {
		command := "go build -o " + target.TargetFileName
		target.BuildCommands = append(target.BuildCommands, command)
	}
}

func (service *GraderService) GetFileSuffix(fileName string) string {
	dotPos := strings.LastIndex(fileName, ".")
	if dotPos != -1 {
		return fileName[dotPos:]
	} else {
		return ""
	}
}

func (service *GraderService) DefaultGCCLinkCommand(rt, outName string, objects []string, linkStdCXX bool, extraOptions []string) string {
	isWindows := runtime.GOOS == "windows"
	isArm := runtime.GOARCH == "arm"
	compilerPrefix := ""
	var linker string
	if !isWindows && rt == "wine" {
		compilerPrefix = "x86_64-w64-mingw32-"
	} else if !isArm && rt == "qemu-arm" {
		compilerPrefix = "arm-linux-gnueabi-"
	}
	if linkStdCXX {
		linker = "g++"
	} else {
		linker = "gcc"
	}
	args := []string{
		compilerPrefix + linker,
		"-o", outName,
	}
	if compilerPrefix == "" {
		args = append(args, "-fsanitize=undefined")
		if !strings.Contains(rt, "valgrind") {
			args = append(args, "-fsanitize=address")
		}
	}
	if extraOptions != nil {
		args = append(args, extraOptions...)
	}
	args = append(args, objects...)
	return strings.Join(args, " ")
}

func (service *GraderService) DefaultGCCCompileCommand(rt string, sourceFileName string, extraOptions []string) string {
	overrideStandard := ""
	for _, opt := range extraOptions {
		if strings.HasPrefix(opt, "-std=") {
			overrideStandard = opt
		}
	}
	isWindows := runtime.GOOS == "windows"
	isArm := runtime.GOARCH == "arm"
	compilerPrefix := ""
	if !isWindows && rt == "wine" {
		compilerPrefix = "x86_64-w64-mingw32-"
	} else if !isArm && rt == "qemu-arm" {
		compilerPrefix = "arm-linux-gnueabi-"
	}
	options := make([]string, 0, 50)
	var compiler string
	fileSuffix := service.GetFileSuffix(sourceFileName)
	if fileSuffix == ".c" || fileSuffix == ".S" {
		compiler = "gcc"
		if overrideStandard != "" {
			options = append(options, overrideStandard)
		} else {
			options = append(options, "-std=gnu11")
		}
	} else {
		compiler = "g++"
		if overrideStandard != "" {
			options = append(options, overrideStandard)
		} else {
			options = append(options, "-std=gnu++17")
		}
	}
	if strings.Contains(rt, "32") && !strings.Contains(rt, "qemu") {
		options = append(options, "-m32")
	}
	options = append(options, "-Werror", "-Wall")
	options = append(options, "-c", "-g", "-O2")
	if compilerPrefix == "" {
		// use sanitizers only for native platforms
		options = append(options, "-fsanitize=undefined", "-fno-sanitize-recover")
	}
	if !isArm {
		options = append(options, "-msse4.2")
	}
	if !strings.Contains(rt, "valgrind") && compilerPrefix == "" {
		// valgrind is not compatible with address sanitizer
		options = append(options, "-fsanitize=address")
	}
	if extraOptions != nil {
		options = append(options, extraOptions...)
	}
	objectFileName := sourceFileName + "." + rt + ".o"
	options = append(options, "-o", objectFileName)
	options = append(options, sourceFileName)
	return compilerPrefix + compiler + " " + strings.Join(options, " ")
}

func (service *GraderService) ServeIncomingSubmissions(ctx context.Context) (err error) {
	graderProps := &GraderProperties{
		Name: service.Worker.GetName(),
		Platform: &GradingPlatform{
			Arch:      service.Worker.GetArch(),
			Os:        service.Worker.GetOs(),
			Runtimes:  service.Worker.GetSupportedRuntimes(),
			Compilers: nil,
			Tools:     nil,
			Libraries: nil,
		},
	}
	ctx = metadata.NewOutgoingContext(ctx, service.ContextMetadata)
	client, err := service.SubmissionsProvider.ReceiveSubmissionsToGrade(ctx, graderProps)
	if err != nil {
		return err
	}
	var submission *Submission
	for {
		submission, err = client.Recv()
		if err != nil {
			return err
		}
		submission, err = service.processSubmission(submission)
		if err != nil {
			return err
		}
		service.SubmissionsProvider.UpdateGraderOutput(ctx, submission)
	}
}

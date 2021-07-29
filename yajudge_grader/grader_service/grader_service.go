package grader_service

import (
	"context"
	"fmt"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"os"
	"strconv"
	"strings"
	yajudge "yajudge/service"
)

type RpcConfig struct {
	Host				string `yaml:"host"`
	Port				uint16 `yaml:"port"`
	PublicToken			string `yaml:"public_token"`
	PrivateToken		string `yaml:"private_token"`
}

type CourseDataCacheItem struct {
	Timestamp			int64
	CourseData			*yajudge.CourseData
}

type GraderService struct {
	SubmissionsProvider	yajudge.SubmissionManagementClient
	CoursesProvider 	yajudge.CourseManagementClient
	ContextMetadata		metadata.MD

	CourseDataCache		map[string]CourseDataCacheItem
	WorkingDirectory	string

	Worker				GraderInterface
}

func NewGraderService() *GraderService {
	return &GraderService{
		CourseDataCache: make(map[string]CourseDataCacheItem),
	}
}

func (service *GraderService) ConnectToMasterService(config RpcConfig) (err error) {
	grpcAddr := config.Host + ":" + strconv.Itoa(int(config.Port))
	grpcConn, err := grpc.Dial(grpcAddr, grpc.WithInsecure())
	if err != nil {
		return err
	}
	submissionManager := yajudge.NewSubmissionManagementClient(grpcConn)
	coursesManager := yajudge.NewCourseManagementClient(grpcConn)
	service.SubmissionsProvider = submissionManager
	service.CoursesProvider = coursesManager
	service.ContextMetadata = metadata.Pairs("auth", config.PrivateToken)
	return nil
}

func (service *GraderService) LoadCourseData(course *yajudge.Course) (result *yajudge.CourseData, err error) {
	var cachedTimestamp int64 = 0
	var cachedCourseData *yajudge.CourseData = nil
	courseDataId := course.CourseData.Id
	if cacheContent, inCache := service.CourseDataCache[courseDataId]; inCache {
		cachedTimestamp = cacheContent.Timestamp
		cachedCourseData = cacheContent.CourseData
	}
	ctx := metadata.NewOutgoingContext(context.Background(), service.ContextMetadata)
	contentResponse, err := service.CoursesProvider.GetCoursePublicContent(ctx,
		&yajudge.CourseContentRequest{
			CourseDataId: courseDataId,
			CachedTimestamp: cachedTimestamp,
		},
	)
	if err != nil {
		return nil, err
	}
	if contentResponse.Status == yajudge.CourseContentStatus_HAS_DATA {
		service.CourseDataCache[courseDataId] = CourseDataCacheItem{
			CourseData: contentResponse.Data,
			Timestamp: contentResponse.LastModified,
		}
		return contentResponse.Data, nil
	} else {
		return cachedCourseData, nil
	}
}

func FindProblemData(course *yajudge.CourseData, problemId string) (result *yajudge.ProblemData) {
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

func (service *GraderService) processSubmission(submission *yajudge.Submission) (result *yajudge.Submission, err error) {
	courseData, err := service.LoadCourseData(submission.Course)
	if err != nil {
		return nil, fmt.Errorf("can't load course '%s' data: %v", submission.Course.CourseData.Id, err)
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
	for _, file := range solution.Files {
		fileName := problemRoot + string(os.PathSeparator) + file.Name
		if err = CreateFileWithPath(fileName, file.Data); err != nil {
			return nil, err
		}
	}

	// 2. Check code style
	styleCheckFailed := false
	styleCheckError := ""
	for _, file := range solution.Files {
		for _, style := range courseData.CodeStyles {
			if strings.HasSuffix(file.Name, style.SourceFileSuffix) {
				ok, report, err := service.Worker.CheckStyle(problemRoot, style, file)
				if err != nil {
					return nil, fmt.Errorf("can't run style check for id '%d': %v", submission.Id, err)
				}
				if !ok {
					styleCheckFailed = true
					styleCheckError = report
					break
				}
			}
		}
	}
	if styleCheckFailed {
		submission.GraderErrors = styleCheckError
		submission.Status = yajudge.SolutionStatus_STYLE_CHECK_ERROR
		return submission, nil
	}

	return submission, nil
}

func (service *GraderService) ServeIncomingSubmissions() (err error) {
	graderProps := &yajudge.GraderProperties{}
	ctx := metadata.NewOutgoingContext(context.Background(), service.ContextMetadata)
	client, err := service.SubmissionsProvider.ReceiveSubmissionsToGrade(ctx, graderProps)
	if err != nil {
		return err
	}
	var submission *yajudge.Submission
	for {
		submission, err = client.Recv();
		if err != nil {
			return err
		}
		submission, err = service.processSubmission(submission)
		if err != nil {
			// TODO log error and continue
		}
		service.SubmissionsProvider.UpdateGraderOutput(ctx, submission)
	}
}
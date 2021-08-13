package core_service

import (
	"context"
	"fmt"
	"strings"
)

type GraderConnection struct {
	Properties *GraderProperties
	Queue      chan *Submission
}

type GradingManager struct {
	Graders       []*GraderConnection
	LastUsedIndex int // for usage balancing

	Services *Services
}

func NewGradingManager(services *Services) *GradingManager {
	return &GradingManager{
		Services:      services,
		LastUsedIndex: -1,
		Graders:       make([]*GraderConnection, 0, 10),
	}
}

func (manager *GradingManager) RegisterNewGrader(properties *GraderProperties) (*GraderConnection, error) {
	grader := &GraderConnection{
		Properties: properties,
		Queue:      make(chan *Submission, 1000),
	}
	manager.Graders = append(manager.Graders, grader)
	return grader, manager.CheckForDelayedSubmissions()
}

func (manager *GradingManager) CheckForDelayedSubmissions() error {
	submissions, err := manager.Services.SubmissionManagement.GetSubmissionsToGrade()
	if err != nil {
		return err
	}
	for _, sub := range submissions {
		graderIndex := (manager.LastUsedIndex + 1) % len(manager.Graders)
		manager.LastUsedIndex = graderIndex
		grader := manager.Graders[graderIndex]
		if manager.GraderCanAcceptSubmission(sub, grader.Properties) {
			_, err = manager.EnqueueSubmissionToGrader(sub, grader)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (manager *GradingManager) ProcessNewSubmission(sub *Submission) (*Submission, error) {
	for i := 0; i < len(manager.Graders); i++ {
		graderIndex := (manager.LastUsedIndex + 1) % len(manager.Graders)
		manager.LastUsedIndex = graderIndex
		grader := manager.Graders[graderIndex]
		if manager.GraderCanAcceptSubmission(sub, grader.Properties) {
			return manager.EnqueueSubmissionToGrader(sub, grader)
		}
	}
	return sub, nil
}

func (manager *GradingManager) GraderCanAcceptSubmission(sub *Submission, props *GraderProperties) bool {
	problem, err := manager.GetProblemDataForSubmission(sub)
	if err != nil {
		return false
	}
	platformMatch := true
	osMatch := true
	platformRequired := problem.GradingOptions.PlatformRequired
	graderPlatform := props.Platform
	if platformRequired.Arch != Arch_ARCH_ANY {
		platformMatch = platformRequired.Arch == graderPlatform.Arch
	}
	if platformRequired.Os != OS_OS_ANY {
		switch platformRequired.Os {
		case OS_OS_WINDOWS:
			osMatch = graderPlatform.Os == OS_OS_WINDOWS
		case OS_OS_LINUX:
			osMatch = graderPlatform.Os == OS_OS_LINUX
		case OS_OS_DARWIN:
			osMatch = graderPlatform.Os == OS_OS_DARWIN
		case OS_OS_BSD:
			osMatch = graderPlatform.Os == OS_OS_BSD
		case OS_OS_POSIX:
			osMatch = graderPlatform.Os != OS_OS_WINDOWS
		}
	}
	runtimesMatch := true
	for _, rt := range problem.GradingOptions.Runtimes {
		if !rt.Optional && !strings.HasPrefix(rt.Name, "default") {
			runtimeFound := false
			for _, grt := range props.Platform.Runtimes {
				if rt.Name == grt {
					runtimeFound = true
					break
				}
			}
			if !runtimeFound {
				runtimesMatch = false
				break
			}
		}
	}
	return platformMatch && osMatch && runtimesMatch
}

func (manager *GradingManager) GetProblemDataForSubmission(sub *Submission) (*ProblemData, error) {
	courseDataIdQuery := `select course_data from courses where id=$1`
	if sub.Course.DataId == "" {
		err := manager.Services.DB.QueryRow(courseDataIdQuery, sub.Course.Id).Scan(&sub.Course.DataId)
		if err != nil {
			return nil, err
		}
	}
	courseRequest := &CourseContentRequest{
		CourseDataId:    sub.Course.DataId,
		CachedTimestamp: 0,
	}
	contentResponse, err := manager.Services.CourseManagement.GetCourseFullContent(context.Background(), courseRequest)
	if err != nil {
		return nil, err
	}
	problem := FindProblemInCourseData(contentResponse.Data, sub.ProblemId)
	if problem == nil {
		return nil, fmt.Errorf("problem '%s' not found in course '%s'", sub.ProblemId, sub.Course.DataId)
	} else {
		return problem, nil
	}
}

func (manager *GradingManager) EnqueueSubmissionToGrader(sub *Submission, grader *GraderConnection) (*Submission, error) {
	sub.Status = SolutionStatus_GRADER_ASSIGNED
	sub.GraderName = grader.Properties.GetName()
	sub, err := manager.Services.SubmissionManagement.UpdateGraderOutput(context.Background(), sub)
	if err != nil {
		return sub, err
	}
	grader.Queue <- sub
	return sub, nil
}

func (manager *GradingManager) DeregisterGrader(grader *GraderConnection) {
	index := -1
	for i, g := range manager.Graders {
		if g == grader {
			index = i
			break
		}
	}
	if index != -1 {
		manager.Graders = append(manager.Graders[:index], manager.Graders[index+1:]...)
	}
	graderName := grader.Properties.GetName()
	query := `
update submissions set status=$1 where grader_name=$2
`
	_, err := manager.Services.DB.Exec(query, SolutionStatus_SUBMITTED, graderName)
	_ = err
}

package core_service

import (
	"context"
	"database/sql"
	"fmt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"strconv"
	"strings"
	"time"
)

type SubmissionManagementService struct {
	DB					*sql.DB
	Services			*Services
}

func (service SubmissionManagementService) GetSubmissions(ctx context.Context, filter *SubmissionFilter) (*SubmissionList, error) {
	// Check user enrollments for specific course
	currentUser, err := service.Services.UserManagement.GetUserFromContext(ctx)
	if err != nil {
		return nil, err
	}
	enrolls, err := service.Services.CourseManagement.GetUserEnrollments(currentUser)
	if err != nil {
		return nil, err
	}
	var courseEnroll *Enrolment = nil
	for _, e := range enrolls {
		if e.Course.Id == filter.Course.Id {
			courseEnroll = e
			break
		}
	}
	if courseEnroll == nil {
		return nil, status.Errorf(codes.PermissionDenied, "user %v not enrolled to course %v", filter.User.Id, filter.Course.Id)
	}
	if courseEnroll.Role == Role_ROLE_STUDENT && filter.User.Id != currentUser.Id {
		return nil, status.Errorf(codes.PermissionDenied, "can't access not own submissions")
	}
	query := `
select submissions.id,
       users_id,problem_id,
       timestamp,
       status,
       users.first_name,
       users.last_name,
       users.mid_name,
       users.group_name from submissions, users
where
		users_id=users.id 
       `
	conditions := make([]string, 0, 5)
	arguments := make([]interface{}, 0, 5)
	conditions = append(conditions, "courses_id=$"+strconv.Itoa(len(conditions)+1))
	arguments = append(arguments, filter.Course.Id)
	if filter.User.Id != 0 {
		conditions = append(conditions, "users_id=$"+strconv.Itoa(len(conditions)+1))
		arguments = append(arguments, filter.User.Id)
	}
	if filter.ProblemId != "" {
		conditions = append(conditions, "problem_id=$"+strconv.Itoa(len(conditions)+1))
		arguments = append(arguments, filter.ProblemId)
	}
	if filter.Status != SolutionStatus_ANY_STATUS {
		conditions = append(conditions, "status=$"+strconv.Itoa(len(conditions)+1))
		arguments = append(arguments, int(filter.Status))
	}
	query += `and ` + strings.Join(conditions, " and ")
	rows, err := service.DB.Query(query, arguments...)
	if err != nil {
		return nil, err
	}
	result := &SubmissionList{Submissions: make([]*Submission, 0)}
	for rows.Next() {
		var id int
		var usersId int
		var problemId string
		var timestamp int64
		var problemStatus int
		var firstName string
		var lastName string
		var midName sql.NullString
		var groupName sql.NullString
		err = rows.Scan(&id, &usersId, &problemId, &timestamp, &problemStatus, &firstName, &lastName, &midName, &groupName)
		if err != nil {
			return nil, err
		}
		submUser := &User{Id: int64(usersId), FirstName: firstName, LastName: lastName}
		if midName.Valid {
			submUser.MidName = midName.String
		}
		if groupName.Valid {
			submUser.GroupName = groupName.String
		}
		subm := Submission{
			Id: int64(id),
			User: submUser,
			Course: courseEnroll.Course,
			Problem: &ProblemData{Id: problemId},
			Timestamp: timestamp,
			Status: SolutionStatus(problemStatus),
			SolutionFiles: &FileSet{Files: make([]*File, 0)},
		}
		result.Submissions = append(result.Submissions, &subm)
	}
	return result, nil
}

func (service SubmissionManagementService) SubmitProblemSolution(ctx context.Context, submission *Submission) (*Submission, error) {
	currentUser, err := service.Services.UserManagement.GetUserFromContext(ctx)
	if err != nil {
		return nil, err
	}
	if submission.User.Id != currentUser.Id {
		return nil, fmt.Errorf("user mismatch")
	}
	enrolls, err := service.Services.CourseManagement.GetUserEnrollments(currentUser)
	if err != nil {
		return nil, err
	}
	var courseEnroll *Enrolment = nil
	for _, e := range enrolls {
		if e.Course.Id == submission.Course.Id {
			courseEnroll = e
			break
		}
	}
	if courseEnroll == nil {
		return nil, status.Errorf(codes.PermissionDenied, "user %v not enrolled to course %v",
			submission.User.Id, submission.Course.Id)
	}
	query := `
insert into submissions(users_id,courses_id,problem_id,status,timestamp)
values ($1,$2,$3,$4,$5)
returning id
`
	err = service.DB.QueryRow(query, currentUser.Id, submission.Course.Id,
		submission.Problem.Id, SolutionStatus_SUBMITTED, time.Now().Unix()).Scan(&submission.Id)
	if err != nil {
		return nil, err
	}
	for _, file := range submission.SolutionFiles.Files {
		fQuery := `
insert into submission_files(file_name,submissions_id,content)
values ($1,$2,$3)
returning id
`
		content := string(file.Data)
		var fileId int64
		err = service.DB.QueryRow(fQuery, file.Name, submission.Id, content).Scan(&fileId)
		if err != nil {
			return nil, err
		}
	}
	return submission, nil
}

func (service SubmissionManagementService) ReceiveSubmissionsToGrade(properties *GraderProperties, server SubmissionManagement_ReceiveSubmissionsToGradeServer) error {
	panic("implement me")
}

func (service SubmissionManagementService) UpdateGraderOutput(ctx context.Context, submission *Submission) (*Submission, error) {
	panic("implement me")
}

func (service SubmissionManagementService) mustEmbedUnimplementedSubmissionManagementServer() {
	panic("implement me")
}

func NewSubmissionsManagementService(services *Services) *SubmissionManagementService {
	return &SubmissionManagementService{
		DB: services.DB,
		Services: services,
	}
}

func (service* SubmissionManagementService) CheckSubmissionsCountLimit(ctx context.Context, request *CheckSubmissionsLimitRequest) (*SubmissionsCountLimit, error) {
	userId := request.User.Id
	courseId := request.Course.Id
	problemId := request.ProblemId
	currentTime := time.Now().Unix()
	minTime := currentTime - 60*60  // minus one hour
	query := `select timestamp from submissions where users_id=$1 and courses_id=$2 and problem_id=$3 and timestamp>=$4 order by timestamp`
	rows, err := service.DB.Query(query, userId, courseId, problemId, minTime)
	if err != nil {
		return nil, err
	}
	submissionsCount := 0
	var earliestSubmission int64 = 0
	var currentSubmission int64
	for rows.Next() {
		submissionsCount += 1
		err := rows.Scan(&currentSubmission)
		if err != nil {
			return nil, err
		}
		if currentSubmission>=minTime && (currentSubmission<=earliestSubmission || earliestSubmission==0) {
			earliestSubmission = currentSubmission
		}
	}
	courseContent, err := service.Services.CourseManagement.GetCoursePublicContent(ctx, &CourseContentRequest{CourseDataId: request.Course.CourseData.Id})
	if err != nil {
		return nil, err
	}
	limit := int(courseContent.Data.MaxSubmissionsPerHour)
	limit = limit - submissionsCount
	if limit < 0 {
		limit = 0
	}
	nextTimeReset := earliestSubmission
	if nextTimeReset != 0 {
		nextTimeReset += 60*60
	}
	result := &SubmissionsCountLimit {
		AttemptsLeft: int32(limit),
		NextTimeReset: nextTimeReset,
		ServerTime: time.Now().Unix(),
	}
	return result, nil
}

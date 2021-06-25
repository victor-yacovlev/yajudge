package core_service

import (
	"context"
	"database/sql"
)

type CourseManagementService struct {
	DB		*sql.DB
}

func (serice *CourseManagementService) CreateOrUpdateSection(ctx context.Context, section *Section) (*Section, error) {
	panic("implement me")
}

func (serice *CourseManagementService) UpdateSectionLessons(ctx context.Context, section *Section) (*Section, error) {
	panic("implement me")
}

func (serice *CourseManagementService) UpdateCourseSections(ctx context.Context, course *Course) (*Course, error) {
	panic("implement me")
}

func (serice *CourseManagementService) CloneCourse(ctx context.Context, course *Course) (*Course, error) {
	panic("implement me")
}

func (serice *CourseManagementService) CreateOrUpdateLesson(ctx context.Context, lesson *Lesson) (*Lesson, error) {
	panic("implement me")
}

func (serice *CourseManagementService) CreateOrUpdateTextReading(ctx context.Context, reading *TextReading) (*TextReading, error) {
	panic("implement me")
}

func (serice *CourseManagementService) CreateOrUpdateProblem(ctx context.Context, problem *Problem) (*Problem, error) {
	panic("implement me")
}

func (serice * CourseManagementService) CreateOrUpdateCourse(ctx context.Context, course *Course) (res *Course, err error) {
	var query string
	res = new(Course)
	if course.Id > 0 {
		query = `update courses set name=$1 where id=$2 returning id`
		err := serice.DB.QueryRow(query, course.Name, course.Id).Scan(&res.Id)
		if err != nil {
			return nil, err
		}
		return res, nil
	} else {
		query = `insert into courses(name) values ($1) returning id`
		err := serice.DB.QueryRow(query, course.Name).Scan(&res.Id)
		if err != nil {
			return nil, err
		}
	}
	return res, nil
}

func (serice *CourseManagementService) EnrollUser(ctx context.Context, request *Enroll) (*Course, error) {
	panic("implement me")
}

func (c CourseManagementService) mustEmbedUnimplementedCourseManagementServer() {
	panic("implement me")
}

func NewCourseManagementService(db *sql.DB) *CourseManagementService {
	return &CourseManagementService{DB: db}
}

package core_service

import (
	"context"
	"database/sql"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type CourseManagementService struct {
	DB 			*sql.DB
	Parent		*Services
}

func (service *CourseManagementService) GetUserEnrollments(user *User) (res []*Enrolment, err error) {
	if user.Id == 0 {
		return nil, status.Errorf(codes.InvalidArgument, "no user id specified")
	}
	q, err := service.DB.Query(
		`select roles.name, courses_id, roles_id from enrollments, roles where users_id=$1 and roles.id=enrollments.roles_id`,
		user.Id)
	if err != nil {
		return nil, err
	}
	defer q.Close()
	res = make([]*Enrolment, 0, 10)
	for q.Next() {
		course := &Course{}
		role := &Role{}
		err = q.Scan(&role.Name, &course.Id, &role.Id)
		if err != nil {
			return nil, err
		}
		role.Capabilities, err = service.Parent.UserManagement.GetRoleCapabilities(role)
		if err != nil {
			return nil, err
		}
		res = append(res, &Enrolment{
			Role: role,
			Course: course,
		})
	}
	return res, err
}

func (service *CourseManagementService) GetCourses(ctx context.Context, filter *CoursesFilter) (res *CoursesList, err error) {
	var enrollments []*Enrolment = nil
	if filter.User != nil && filter.User.Id > 0 {
		enrollments, err = service.GetUserEnrollments(filter.User)
		if err != nil {
			return nil, err
		}
	}
	allCourses, err := service.DB.Query(`select id, name from courses`)
	if err != nil {
		return nil, err
	}
	defer allCourses.Close()
	res = new(CoursesList)
	res.Courses = make([]*CoursesList_CourseListEntry, 0, 10)
	for allCourses.Next() {
		candidate := new(Course)
		err = allCourses.Scan(&candidate.Id, &candidate.Name)
		if err != nil {
			return nil, err
		}
		courseRole := &Role{}
		if enrollments != nil {
			enrollmentFound := false
			for _, enr := range enrollments {
				if enr.Course.Id == candidate.Id {
					enrollmentFound = true
					courseRole = enr.Role
					break
				}
			}
			if !enrollmentFound {
				continue
			}
		} else if filter.User != nil && filter.User.Id > 0 {
			courseRole, err = service.Parent.UserManagement.GetDefaultRole(filter.User)
			if err != nil {
				return nil, err
			}
		}
		if filter.Course != nil && filter.Course.Id > 0 {
			// must match by exact course id
			if filter.Course.Id != candidate.Id {
				continue
			}
		}
		if filter.Course != nil && filter.Course.Name != "" {
			// must math by course name
			if !PartialStringMatch(filter.PartialStringMatch, candidate.Name, filter.Course.Name) {
				continue
			}
		}
		res.Courses = append(res.Courses, &CoursesList_CourseListEntry{
			Course: candidate,
			Role: courseRole,
		})
	}
	return res, err
}

func (service *CourseManagementService) CreateOrUpdateSection(ctx context.Context, section *Section) (*Section, error) {
	panic("implement me")
}

func (service *CourseManagementService) UpdateSectionLessons(ctx context.Context, section *Section) (*Section, error) {
	panic("implement me")
}

func (service *CourseManagementService) UpdateCourseSections(ctx context.Context, course *Course) (*Course, error) {
	panic("implement me")
}

func (service *CourseManagementService) CloneCourse(ctx context.Context, course *Course) (*Course, error) {
	panic("implement me")
}

func (service *CourseManagementService) CreateOrUpdateLesson(ctx context.Context, lesson *Lesson) (*Lesson, error) {
	panic("implement me")
}

func (service *CourseManagementService) CreateOrUpdateTextReading(ctx context.Context, reading *TextReading) (*TextReading, error) {
	panic("implement me")
}

func (service *CourseManagementService) CreateOrUpdateProblem(ctx context.Context, problem *Problem) (*Problem, error) {
	panic("implement me")
}

func (service *CourseManagementService) CreateOrUpdateCourse(ctx context.Context, course *Course) (res *Course, err error) {
	var query string
	res = new(Course)
	if course.Id > 0 {
		query = `update courses set name=$1 where id=$2 returning id`
		err := service.DB.QueryRow(query, course.Name, course.Id).Scan(&res.Id)
		if err != nil {
			return nil, err
		}
		return res, nil
	} else {
		query = `insert into courses(name) values ($1) returning id`
		err := service.DB.QueryRow(query, course.Name).Scan(&res.Id)
		if err != nil {
			return nil, err
		}
	}
	return res, nil
}

func (service *CourseManagementService) EnrollUser(ctx context.Context, request *Enroll) (course *Course, err error) {
	user := request.User
	course = request.Course
	role := request.Role
	if user.Id==0 && user.Email=="" {
		return nil, status.Errorf(codes.InvalidArgument, "user id or email required")
	} else if request.User.Id==0 {
		err = service.DB.QueryRow(`select id from users where email=$1`, user.Email).Scan(&user.Id)
		if err != nil {
			return nil, err
		}
	}
	if role.Id==0 && role.Name=="" {
		return nil, status.Errorf(codes.InvalidArgument, "role id or name required")
	} else if role.Id==0 {
		err = service.DB.QueryRow(`select id from roles where name=$1`, role.Name).Scan(&role.Id)
		if err != nil {
			return nil, err
		}
	}
	if course.Id==0 && course.Name=="" {
		return nil, status.Errorf(codes.InvalidArgument, "course id or name required")
	}
	if course.Id==0 {
		err = service.DB.QueryRow(`select id from courses where name=$1`, course.Name).Scan(&course.Id)
		if err != nil {
			return nil, err
		}
	}
	if course.Name=="" {
		err = service.DB.QueryRow(`select name from courses where id=$1`, course.Id).Scan(&course.Name)
		if err != nil {
			return nil, err
		}
	}
	_, err = service.DB.Exec(`insert into enrollments(courses_id, users_id, roles_id) values ($1,$2,$3)`,
		course.Id, user.Id, role.Id)
	return course, err
}

func (service CourseManagementService) mustEmbedUnimplementedCourseManagementServer() {
	panic("implement me")
}

func NewCourseManagementService(parent *Services) *CourseManagementService {
	return &CourseManagementService{DB: parent.DB, Parent: parent}
}

package core_service

import (
	"context"
	"database/sql"
	"fmt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type CourseManagementService struct {
	DB 			*sql.DB
	Parent		*Services
}

func (service *CourseManagementService) DeleteCourse(ctx context.Context, course *Course) (*Nothing, error) {
	if course.Id==0 {
		return nil, status.Errorf(codes.InvalidArgument, "course id required")
	}
	_, err := service.DB.Exec(`delete from courses where id=$1`, course.Id)
	if err != nil {
		return nil, err
	}
	return &Nothing{}, nil
}

func (service *CourseManagementService) GetUserEnrollments(user *User) (res []*Enrolment, err error) {
	if user.Id == 0 {
		return nil, status.Errorf(codes.InvalidArgument, "no user id specified")
	}
	q, err := service.DB.Query(
		`select courses_id, role from enrollments where users_id=$1`, user.Id)
	if err != nil {
		return nil, err
	}
	defer q.Close()
	res = make([]*Enrolment, 0, 10)
	for q.Next() {
		course := &Course{}
		role := 0
		err = q.Scan(&course.Id, &role)
		if err != nil {
			return nil, err
		}
		if err != nil {
			return nil, err
		}
		res = append(res, &Enrolment{
			Role: Role(role),
			Course: course,
		})
	}
	return res, err
}

func (service *CourseManagementService) GetSectionLessons(section *Section) (res []*Lesson, err error) {
	if section ==nil || section.Id==0 {
		return nil, fmt.Errorf("bad section: nil or no section.id")
	}
	q, err := service.DB.Query(
		`select id, name, show_after_id, open_date, soft_deadline, hard_deadline from lessons where sections_id=$1 order by show_after_id;`,
		section.Id)
	if err != nil {
		return nil, err
	}
	defer q.Close()
	res = make([]*Lesson, 0, 20)
	for q.Next() {
		lesson := &Lesson{}
		var openDate, softDeadline, hardDeadline sql.NullInt64
		err = q.Scan(&lesson.Id, &lesson.Name, &lesson.ShowAfterId, &openDate, &softDeadline, &hardDeadline)
		if err != nil {
			return nil, err
		}
		if openDate.Valid {
			lesson.OpenDate = openDate.Int64
		}
		if softDeadline.Valid {
			lesson.SoftDeadline = softDeadline.Int64
		}
		if hardDeadline.Valid {
			lesson.HardDeadline = hardDeadline.Int64
		}
		res = append(res, lesson)
	}
	return res, err
}


func (service *CourseManagementService) GetCourseSections(course *Course) (res []*Section, err error) {
	if course==nil || course.Id==0 {
		return nil, fmt.Errorf("bad course: nil or no course.id")
	}
	q, err := service.DB.Query(
		`select id, name, show_after_id from sections where courses_id=$1 order by show_after_id;`,
		course.Id)
	if err != nil {
		return nil, err
	}
	defer q.Close()
	res = make([]*Section, 0, 20)
	for q.Next() {
		section := &Section{}
		err = q.Scan(&section.Id, &section.Name, &section.ShowAfterId)
		if err != nil {
			return nil, err
		}
		res = append(res, section)
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
		var courseRole Role
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


func (service *CourseManagementService) CloneCourse(ctx context.Context, course *Course) (res *Course, err error) {
	// todo make deep contents copy
	if course.Id==0 {
		return nil, status.Errorf(codes.InvalidArgument, "course id required")
	}
	if course.CourseData == nil {
		course.CourseData = &CourseData{}
	}
	if course.Name=="" {
		err = service.DB.QueryRow(`select name,course_data from courses where id=$1`, course.Id).Scan(&course.Name, &course.CourseData.Id)
		if err != nil {
			return nil, err
		}
	}
	newName, err := MakeEntryCopyName(service.DB, "courses", course.Name)
	if err != nil {
		return nil, err
	}
	res = &Course{Name: newName}
	err = service.DB.QueryRow(`insert into courses(name,course_data) values ($1,$2) returning id`, newName, course.CourseData.Id).Scan(&res.Id)
	if err != nil {
		return nil, err
	}
	return res, err
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
		query = `insert into courses(name,course_data) values ($1,$2) returning id`
		err := service.DB.QueryRow(query, course.Name, course.CourseData.Id).Scan(&res.Id)
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
	if role == 0 {
		return nil, status.Errorf(codes.InvalidArgument, "role id or name required")
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
	_, err = service.DB.Exec(`insert into enrollments(courses_id, users_id, role) values ($1,$2,$3)`,
		course.Id, user.Id, role)
	return course, err
}

func (service CourseManagementService) mustEmbedUnimplementedCourseManagementServer() {
	panic("implement me")
}

func NewCourseManagementService(parent *Services) *CourseManagementService {
	return &CourseManagementService{DB: parent.DB, Parent: parent}
}

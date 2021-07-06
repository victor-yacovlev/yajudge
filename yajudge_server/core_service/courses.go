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

func (service *CourseManagementService) DeleteSection(ctx context.Context, section *Section) (*Nothing, error) {
	if section.Id==0 {
		return nil, status.Errorf(codes.InvalidArgument, "section id required")
	}
	_, err := service.DB.Exec(`delete from sections where id=$1`, section.Id)
	if err != nil {
		return nil, err
	}
	return &Nothing{}, nil
}

func (service *CourseManagementService) DeleteLesson(ctx context.Context, lesson *Lesson) (*Nothing, error) {
	if lesson.Id==0 {
		return nil, status.Errorf(codes.InvalidArgument, "lesson id required")
	}
	_, err := service.DB.Exec(`delete from lessons where id=$1`, lesson.Id)
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

func (service *CourseManagementService) CreateOrUpdateSection(ctx context.Context, section *Section) (res *Section, err error) {
	res = new(Section)
	fields := make([]string, 0, 10)
	vals := make([]interface{}, 0, 10)
	fields = append(fields, "name")
	vals = append(vals, section.Name)
	fields = append(fields, "show_after_id")
	vals = append(vals, section.ShowAfterId)
	if section.OpenDate != 0 {
		fields = append(fields, "open_date")
		vals = append(vals, section.OpenDate)
	}
	if section.OpenDate != 0 {
		fields = append(fields, "soft_deadline")
		vals = append(vals, section.SoftDeadline)
	}
	if section.OpenDate != 0 {
		fields = append(fields, "hard_deadline")
		vals = append(vals, section.HardDeadline)
	}
	if section.Id > 0 {
		err = QueryForTableItemUpdate(service.DB, "sections", section.Id, fields, vals)
		if err != nil {
			return nil, err
		}
		return res, nil
	} else {
		res.Id, err = QueryForTableItemInsert(service.DB, "sections", fields, vals)
		if err != nil {
			return nil, err
		}
	}
	return res, nil
}


func (service *CourseManagementService) CloneCourse(ctx context.Context, course *Course) (res *Course, err error) {
	// todo make deep contents copy
	if course.Id==0 {
		return nil, status.Errorf(codes.InvalidArgument, "course id required")
	}
	if course.Name=="" {
		err = service.DB.QueryRow(`select name from courses where id=$1`, course.Id).Scan(&course.Name)
		if err != nil {
			return nil, err
		}
	}
	newName, err := MakeEntryCopyName(service.DB, "courses", course.Name)
	if err != nil {
		return nil, err
	}
	res = &Course{Name: newName}
	err = service.DB.QueryRow(`insert into courses(name) values ($1) returning id`, newName).Scan(&res.Id)
	if err != nil {
		return nil, err
	}
	return res, err
}

func (service *CourseManagementService) CreateOrUpdateLesson(ctx context.Context, lesson *Lesson) (res *Lesson, err error) {
	res = new(Lesson)
	fields := make([]string, 0, 10)
	vals := make([]interface{}, 0, 10)
	fields = append(fields, "name")
	vals = append(vals, lesson.Name)
	fields = append(fields, "show_after_id")
	vals = append(vals, lesson.ShowAfterId)
	if lesson.OpenDate != 0 {
		fields = append(fields, "open_date")
		vals = append(vals, lesson.OpenDate)
	}
	if lesson.OpenDate != 0 {
		fields = append(fields, "soft_deadline")
		vals = append(vals, lesson.SoftDeadline)
	}
	if lesson.OpenDate != 0 {
		fields = append(fields, "hard_deadline")
		vals = append(vals, lesson.HardDeadline)
	}
	if lesson.Id > 0 {
		err = QueryForTableItemUpdate(service.DB, "lessons", lesson.Id, fields, vals)
		if err != nil {
			return nil, err
		}
		return res, nil
	} else {
		res.Id, err = QueryForTableItemInsert(service.DB, "lessons", fields, vals)
		if err != nil {
			return nil, err
		}
	}
	return res, nil
}

func (service *CourseManagementService) CreateOrUpdateTextReading(ctx context.Context, reading *TextReading) (res *TextReading, err error) {
	if reading.Id == 0 {
		if reading.LessonsId == 0 {
			return nil, status.Errorf(codes.InvalidArgument, "lesson id is required")
		}
		if reading.Title == "" {
			return nil, status.Errorf(codes.InvalidArgument, "title is required")
		}
		if reading.ContentType == "" {
			return nil, status.Errorf(codes.InvalidArgument, "content-type is required")
		}
		if reading.Data=="" && reading.ExternalUrl=="" {
			return nil, status.Errorf(codes.InvalidArgument, "content or external URL is required")
		}
	}
	res = new(TextReading)
	fields := make([]string, 0, 10)
	vals := make([]interface{}, 0, 10)
	if reading.Title!="" {
		fields = append(fields, "title")
		vals = append(vals, reading.Title)
	}
	if reading.ContentType!="" {
		fields = append(fields, "content_type")
		vals = append(vals, reading.ContentType)
	}
	if reading.Data!="" {
		fields = append(fields, "data")
		vals = append(vals, reading.Data)
	}
	if reading.Data!="" {
		fields = append(fields, "external_url")
		vals = append(vals, reading.ExternalUrl)
	}
	if reading.Id > 0 {
		err = QueryForTableItemUpdate(service.DB, "text_readings", reading.Id, fields, vals)
		if err != nil {
			return nil, err
		}
		return res, nil
	} else {
		res.Id, err = QueryForTableItemInsert(service.DB, "text_readings", fields, vals)
		if err != nil {
			return nil, err
		}
	}
	return res, nil
}

func (service *CourseManagementService) CreateOrUpdateProblem(ctx context.Context, problem *Problem) (res *Problem, err error) {
	res = new(Problem)
	fields := make([]string, 0, 10)
	vals := make([]interface{}, 0, 10)
	fields = append(fields, "name")
	vals = append(vals, problem.Name)
	fields = append(fields, "show_after_id")
	vals = append(vals, problem.ShowAtferId)
	if problem.OpenDate != 0 {
		fields = append(fields, "open_date")
		vals = append(vals, problem.OpenDate)
	}
	if problem.OpenDate != 0 {
		fields = append(fields, "soft_deadline")
		vals = append(vals, problem.SoftDeadline)
	}
	if problem.OpenDate != 0 {
		fields = append(fields, "hard_deadline")
		vals = append(vals, problem.HardDeadline)
	}
	fields = append(fields, "blocks_positive_mark")
	vals = append(vals, problem.BlocksPositiveMark)
	fields = append(fields, "blocks_next_problem")
	vals = append(vals, problem.BlocksNextProblem)
	fields = append(fields, "accept_partial_tests")
	vals = append(vals, problem.AcceptPartialTests)
	fields = append(fields, "skip_solution_defence")
	vals = append(vals, problem.SkipSolutionDefence)
	fields = append(fields, "skip_code_review")
	vals = append(vals, problem.SkipCodeReview)
	if problem.Id > 0 {
		err = QueryForTableItemUpdate(service.DB, "problems", problem.Id, fields, vals)
		if err != nil {
			return nil, err
		}
		return res, nil
	} else {
		res.Id, err = QueryForTableItemInsert(service.DB, "problems", fields, vals)
		if err != nil {
			return nil, err
		}
	}
	return res, nil
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

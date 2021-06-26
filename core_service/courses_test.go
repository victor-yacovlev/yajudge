package core_service

import (
	"context"
	"strings"
	"testing"
)

type ServiceTestClients struct {
	Courses      CourseManagementClient
	Users        UserManagementClient
	AdminContext context.Context
	Finish       context.CancelFunc
}

func createCoursesTestClientAndAdminContext(t *testing.T) ServiceTestClients {
	var err error
	servicesContext, finish := context.WithCancel(context.Background())
	services, err := StartServices(servicesContext, listenAddress, authorizationToken, testDatabaseProps)
	if err != nil {
		t.Fatalf("Can't start core_service: %v", err)
	}

	createTestUsers(t, services)
	conn := createTestClientConnection(t)
	client := NewCourseManagementClient(conn)
	usersClient := NewUserManagementClient(conn)
	ctx := createTestContext()

	adminSession, err := usersClient.Authorize(ctx, &User{Email: "info@kremlin.org", Password: "qwerty"})
	if err != nil {
		t.Fatalf("can't authorize admin user: %v", err)
	}
	adminCtx := UpdateContextWithSession(ctx, adminSession)
	return ServiceTestClients {
		Courses:      client,
		Users:        usersClient,
		AdminContext: adminCtx,
		Finish:       finish,
	}
}

func TestCourseCreation(t *testing.T) {
	api := createCoursesTestClientAndAdminContext(t)
	defer api.Finish()

	// 1 Create new course
	course1, err := api.Courses.CreateOrUpdateCourse(api.AdminContext, &Course{Name: "Курс 1"})
	if err != nil {
		t.Fatalf("1: can't create course: %v", err)
	}

	// 2 Get courses list: it must have just one course
	coursesList2, err := api.Courses.GetCourses(api.AdminContext, &CoursesFilter{})
	if err != nil {
		t.Fatalf("2: can't get courses list: %v", err)
	}

	if len(coursesList2.Courses) != 1 {
		t.Fatalf("2: courses list len != 1")
	}
	if coursesList2.Courses[0].Course.Name != "Курс 1" {
		t.Errorf("2: course name mismatch")
	}
	if coursesList2.Courses[0].Course.Id != course1.Id {
		t.Errorf("2: course name mismatch")
	}

	// 3 Rename course
	course3, err := api.Courses.CreateOrUpdateCourse(api.AdminContext, &Course{Id: course1.Id, Name: "Переименованный курс"})
	if err != nil {
		t.Fatalf("3: can't rename course: %v", err)
	}
	if course3.Id != course1.Id {
		t.Fatalf("3: course id changed after renaming")
	}

	// 4 Get courses list again - search by name pattern
	coursesList4, err := api.Courses.GetCourses(api.AdminContext, &CoursesFilter{Course: &Course{Name: "рёиме"}, PartialStringMatch: true})
	if err != nil {
		t.Fatalf("4: can't get courses list: %v", err)
	}
	if len(coursesList4.Courses) != 1 {
		t.Fatalf("4: courses list len != 1")
	}
	if coursesList4.Courses[0].Course.Name != "Переименованный курс" {
		t.Errorf("4: course name mismatch")
	}
	if coursesList4.Courses[0].Course.Id != course1.Id {
		t.Errorf("4: course id mismatch")
	}
}

func TestCourseEnrollment(t *testing.T) {
	api := createCoursesTestClientAndAdminContext(t)
	defer api.Finish()

	// 1 Create new course
	course1, err := api.Courses.CreateOrUpdateCourse(api.AdminContext, &Course{Name: "Курс 1"})
	if err != nil {
		t.Fatalf("1: can't create course: %v", err)
	}

	// 2 Find some student to enroll
	usersList2, err := api.Users.GetUsers(api.AdminContext, &UsersFilter{User: &User{Email: "vasya@lozkin.ru"}})
	if err != nil {
		t.Fatalf("2: can't get existing user: %v", err)
	}
	if len(usersList2.Users) != 1 || usersList2.Users[0].Id == 0 {
		t.Fatalf("2: can't get valid id for existing user")
	}

	// 3 Enroll student to course
	course3, err := api.Courses.EnrollUser(api.AdminContext, &Enroll{
		User:   usersList2.Users[0],
		Role:   &Role{Name: "Учебный ассистент"},
		Course: course1,
	})
	if err != nil {
		t.Fatalf("3: can't enroll user: %v", err)
	}

	// 4 Create student's context and get courses list by himself
	session4, err := api.Users.Authorize(createTestContext(), &User{Email: "vasya@lozkin.ru", Password: "qwerty"})
	if err != nil {
		t.Fatalf("4: can't authorize user: %v", err)
	}
	userContext4 := UpdateContextWithSession(createTestContext(), session4)
	user4, err := api.Users.GetProfile(userContext4, session4)
	if err != nil {
		t.Fatalf("4: can't get user's self profile: %v", err)
	}
	coursesList4, err := api.Courses.GetCourses(userContext4, &CoursesFilter{
		User: &User{Id: user4.Id},
	})
	if err != nil {
		t.Fatalf("4: can't get user courses list: %v", err)
	}
	if len(coursesList4.Courses) != 1 {
		t.Fatalf("4: courses list len mismath")
	}
	if coursesList4.Courses[0].Course.Name != course3.Name {
		t.Errorf("4: course name mismatch")
	}
	if coursesList4.Courses[0].Role.Name != "Учебный ассистент" {
		t.Errorf("4: course role mismatch")
	}
}

func TestCloneAndDeleteCourse(t *testing.T) {
	api := createCoursesTestClientAndAdminContext(t)
	defer api.Finish()

	// 1 Create new course
	course1, err := api.Courses.CreateOrUpdateCourse(api.AdminContext, &Course{Name: "Курс 1"})
	if err != nil {
		t.Fatalf("1: can't create course: %v", err)
	}

	// 2 check if courses count == 1
	coursesList2, err := api.Courses.GetCourses(api.AdminContext, &CoursesFilter{})
	if err != nil {
		t.Fatalf("2: can't get courses list: %v", err)
	}
	if len(coursesList2.Courses)!=1 {
		t.Fatalf("courses count not 1 after creation")
	}

	// 3 clone course
	course3, err := api.Courses.CloneCourse(api.AdminContext, &Course{Id: course1.Id})
	if err != nil {
		t.Fatalf("3: can't clone course: %v", err)
	}

	// 4 check if courses count == 2 and their names almout match
	coursesList4, err := api.Courses.GetCourses(api.AdminContext, &CoursesFilter{})
	if err != nil {
		t.Fatalf("4: can't get courses list: %v", err)
	}
	if len(coursesList4.Courses)!=2 {
		t.Fatalf("courses count not 2 after creation")
	}
	nameFirst := coursesList4.Courses[0].Course.Name
	nameSecond := coursesList4.Courses[1].Course.Name
	if !strings.Contains(nameSecond, nameFirst) {
		t.Fatalf("4: courses names not partial match")
	}

	// 5 delete course
	_, err = api.Courses.DeleteCourse(api.AdminContext, course3)
	if err != nil {
		t.Fatalf("5: can't delete course: %v", err)
	}

	// 6 check if courses count == 1 and their names almout match
	coursesList6, err := api.Courses.GetCourses(api.AdminContext, &CoursesFilter{})
	if err != nil {
		t.Fatalf("6: can't get courses list: %v", err)
	}
	if len(coursesList6.Courses)!=1 {
		t.Fatalf("courses count not 1 after delete")
	}
}

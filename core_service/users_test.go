package core_service

import (
	"context"
	"google.golang.org/grpc/metadata"
	"strings"
	"testing"
)

func createTestUsers(t *testing.T, services *Services) {
	var err error
	services.CreateEmptyDatabase()
	services.CreateStandardRoles()

	query := `
insert into users(first_name, last_name, email, group_name, password) 
values
       /* plain text password starting with = */
       ('Вася', 'Ложкинъ', 'vasya@lozkin.ru', 'Б05-923', '=qwerty'), 
       /* standard password 'qwerty' encoded as sha512 hex */
       ('Вова', 'Пэ', 'info@kremlin.org', NULL, '0dd3e512642c97ca3f747f9a76e374fbda73f9292823c0313be9d78add7cdd8f72235af0c553dd26797e78e1854edee0ae002f8aba074b066dfce1af114e32f8'),       
       /* empty passwords are fobidden to login */
       ('Invalid', 'Password', 'invalid@example.com', NULL, ''), 
       /* to check partial name matching */
       ('Жунурбек', 'Ёбаны-оглы', 'deduske@na-derevnyu.kg', 'Б05-921', '=qwerty'),
       ('Хасан', 'Джумбашвили', 'ded-hasan@mafia.ge', 'Б05-921а', '=qwerty')
       ;
`
	_, err = services.UserManagement.DB.Exec(query)
	if err != nil {
		t.Fatalf("Can't prepare test data in database: %v", err)
	}
	ctx := context.Background()
	services.UserManagement.SetUserDefaultRole(ctx, &UserRole{User: &User{Id: 1}, Role: &Role{Name: "Студент"}})
	services.UserManagement.SetUserDefaultRole(ctx, &UserRole{User: &User{Id: 2}, Role: &Role{Name: "Администратор"}})
	services.UserManagement.SetUserDefaultRole(ctx, &UserRole{User: &User{Id: 4}, Role: &Role{Name: "Студент"}})
	services.UserManagement.SetUserDefaultRole(ctx, &UserRole{User: &User{Id: 5}, Role: &Role{Name: "Студент"}})
}

func updateContextWithSession(ctx context.Context, session *Session) context.Context {
	oldMd, _ := metadata.FromOutgoingContext(ctx)
	md := metadata.Pairs("session", session.Cookie)
	return metadata.NewOutgoingContext(ctx, metadata.Join(oldMd, md))
}

func TestUserAuthorization(t *testing.T) {
	var err error
	servicesContext, finish := context.WithCancel(context.Background())
	services, err := StartServices(servicesContext, listenAddress, authorizationToken, testDatabaseProps)
	if err != nil {
		t.Fatalf("Can't start core_service: %v", err)
	}
	defer finish()

	createTestUsers(t, services)
	conn := createTestClientConnection(t)
	client := NewUserManagementClient(conn)
	ctx := createTestContext()


	type testAuthCase struct {
		In		*User
		Out		*Session
		Err		string
	}

	testData := []testAuthCase{
		// 0 expected err: password not provided
		{In: &User{Email: "vasya@lozkin.ru"}, Out: nil, Err: "password not provided"},
		// 1 expected err: id or email not provided
		{In: &User{FirstName: "Вася"}, Out: nil, Err: "id or email not provided"},
		// 2 expected new session
		{In: &User{Email: "vasya@lozkin.ru", Password: "qwerty"}, Out: &Session{}, Err: ""},
		// 3 expected new session again
		{In: &User{Id: 1, Password: "qwerty"}, Out: &Session{}, Err: ""},
		// 4 expected err: wrong password
		{In: &User{Id: 1, Password: "qwerty123"}, Out: nil, Err: "wrong password"},
		// 5 expected new session
		{In: &User{Email: "info@kremlin.org", Password: "qwerty"}, Out: &Session{}, Err: ""},
		// 6 expected wrong password
		{In: &User{Email: "invalid@example.com", Password: "qwerty"}, Out: nil, Err: "wrong password"},
		// 7 expected user not found
		{In: &User{Email: "invalid123@example.com", Password: "qwerty"}, Out: nil, Err: "user not found"},
		// 8 expected user not found
		{In: &User{Id: 500, Password: "qwerty"}, Out: nil, Err: "user not found"},
	}

	for index, test := range testData {
		res, err := client.Authorize(ctx, test.In)
		if err != nil && test.Err == "" {
			t.Errorf("[Test case %d]: got error '%s', expected no error", index, err.Error())
		} else if err == nil && test.Err != "" {
			t.Errorf("[Test case %d]: got no error, expected error '%s'", index, test.Err)
		} else if err != nil && test.Err != "" && !strings.Contains(err.Error(), test.Err) {
			t.Errorf("[Test case %d]: got error '%s', expected error '%s'", index, err.Error(), test.Err)
		}
		if res == nil && test.Out != nil {
			t.Errorf("[Test case %d]: expected not-nil result, got nil", index)
		} else if res != nil && test.Out == nil {
			t.Errorf("[Test case %d]: expected nil result, got '%v'", index, test.Out)
		}
		if test.Out != nil {
			// check for session created propertly
			res.UserId = 0  // to test find user_id by cookie
			loggedCtx := updateContextWithSession(ctx, res)
			user, err := client.GetProfile(updateContextWithSession(loggedCtx, test.Out), res)
			if err != nil {
				t.Errorf("[Test case %d]: can't get profile for created session: '%v'", index, err)
			} else if user.Id != test.In.Id && user.Email != test.In.Email {
				t.Errorf("[Test case %d]: wrong user session created", index)
			}
		}
	}
}

func TestGetAllUsers(t *testing.T) {
	var err error
	servicesContext, finish := context.WithCancel(context.Background())
	services, err := StartServices(servicesContext, listenAddress, authorizationToken, testDatabaseProps)
	if err != nil {
		t.Fatalf("Can't start core_service: %v", err)
	}
	defer finish()

	createTestUsers(t, services)
	conn := createTestClientConnection(t)
	client := NewUserManagementClient(conn)
	ctx := createTestContext()

	// 1 not authorized users can't get all users
	res1, err := client.GetUsers(ctx, &UsersFilter{})
	if err == nil {
		t.Errorf("[Test case 1]: must be unauthorized error, got result")
		_ = res1
	}

	// 2 make Administrator authorization first and get list of all users
	adminSession, err := client.Authorize(ctx, &User{Email: "info@kremlin.org", Password: "qwerty"})
	if err != nil {
		t.Fatalf("[Test case 2]: can't authorize admin user")
	}
	adminCtx := updateContextWithSession(ctx, adminSession)
	res2, err := client.GetUsers(adminCtx, &UsersFilter{})
	if err != nil {
		t.Errorf("[Test case 2]: can't get users list by admin session")
	} else {
		if len(res2.Users) != 5 {
			t.Errorf("[Test case 2]: result mismatch")
		}
	}

	// 3 reuse Admin authorization to get list of Students only
	res3, err := client.GetUsers(adminCtx, &UsersFilter{Role: &Role{Name: "Студент"}})
	if err != nil {
		t.Errorf("[Test case 3]: can't get users list by admin session")
	} else {
		if len(res3.Users) != 3 {
			t.Errorf("[Test case 3]: result mismatch")
		}
	}

	// 4 regular users must have an error
	regularSession, err := client.Authorize(ctx, &User{Email: "vasya@lozkin.ru", Password: "qwerty"})
	if err != nil {
		t.Fatalf("[Test case 4]: can't authorize regular user")
	}
	regularCtx := updateContextWithSession(ctx, regularSession)
	res4, err := client.GetUsers(regularCtx, &UsersFilter{})
	if err == nil {
		t.Errorf("[Test case 4]: must be an error while getting all users by regular user")
		_ = res4
	}

	// 5 find by soft name matching
	filter5 := &UsersFilter{
		PartialStringMatch: true,
		Role: &Role{Name: "Студент"},
		User: &User{
			FirstName: "бек",
			LastName: "ебаны",
		},
	}
	res5, err := client.GetUsers(adminCtx, filter5)
	if err != nil {
		t.Errorf("[Test case 5]: can't get users list by admin session")
	} else {
		if len(res5.Users) != 1 {
			t.Errorf("[Test case 5]: result mismatch")
		}
	}

	// 6 find only stundents from group 921
	filter6 := &UsersFilter{
		PartialStringMatch: true,
		Role: &Role{Name: "Студент"},
		User: &User{GroupName: "921"},
	}
	res6, err := client.GetUsers(adminCtx, filter6)
	if err != nil {
		t.Errorf("[Test case 6]: can't get users list by admin session")
	} else {
		if len(res6.Users) != 2 {
			t.Errorf("[Test case 6]: result mismatch")
		}
	}
}

func TestUserCreation(t *testing.T) {
	var err error
	servicesContext, finish := context.WithCancel(context.Background())
	services, err := StartServices(servicesContext, listenAddress, authorizationToken, testDatabaseProps)
	if err != nil {
		t.Fatalf("Can't start core_service: %v", err)
	}
	defer finish()

	createTestUsers(t, services)
	conn := createTestClientConnection(t)
	client := NewUserManagementClient(conn)
	ctx := createTestContext()

	adminSession, err := client.Authorize(ctx, &User{Email: "info@kremlin.org", Password: "qwerty"})
	if err != nil {
		t.Fatalf("can't authorize admin user: %v", err)
	}
	adminCtx := updateContextWithSession(ctx, adminSession)
	studentsBefore, err := client.GetUsers(adminCtx, &UsersFilter{Role: &Role{Name: "Студент"}})
	if err != nil {
		t.Fatalf("can't get initial data before manipulations: %v", err)
	}
	initialStudentsCount := len(studentsBefore.Users)

	// Add new student user
	createdUser, err := client.CreateOrUpdateUser(adminCtx, &User{
		FirstName: "Вася",
		LastName: "Пупкин",
		MidName: "Батькович",
		Email: "vapu@fizteh.edu",
		GroupName: "925",
		Password: "qwerty",
	})
	if err != nil {
		t.Fatalf("can't create new user: %v", err)
	}
	_, err = client.SetUserDefaultRole(adminCtx, &UserRole{
		User: &User{Id: createdUser.Id},
		Role: &Role{Name: "Студент"},
	})
	if err != nil {
		t.Fatalf("can't set user role: %v", err)
	}

	studentsAfter, err := client.GetUsers(adminCtx, &UsersFilter{Role: &Role{Name: "Студент"}})
	if err != nil {
		t.Fatalf("can't get data after manipulations: %v", err)
	}
	updatedStudentsCount := len(studentsAfter.Users)
	if (updatedStudentsCount-initialStudentsCount)!=1 {
		t.Fatalf("users count not changed after user creation")
	}
	listToFind, err := client.GetUsers(adminCtx, &UsersFilter{User: &User{Email: "vapu@fizteh.edu"}})
	if err != nil {
		t.Fatalf("can't get data after manipulations: %v", err)
	}
	if len(listToFind.Users)!=1 {
		t.Fatalf("not found created user")
	}
	createdUser = listToFind.Users[0]
	if createdUser.FirstName!="Вася" {
		t.Errorf("first name mismatch")
	}
	if createdUser.LastName!="Пупкин" {
		t.Errorf("last name mismatch")
	}

	// try to rename user and change he's email
	_, err = client.CreateOrUpdateUser(adminCtx, &User{Id: createdUser.Id, FirstName: "Вова", Email: "vopu@fizteh.edu"})
	if err != nil {
		t.Fatalf("can't update user: %v", err)
	}

	listWithUpdated, err := client.GetUsers(adminCtx, &UsersFilter{User: &User{Email: "vopu@fizteh.edu"}})
	if err != nil {
		t.Fatalf("can't get data after manipulations: %v", err)
	}
	if len(listToFind.Users)!=1 {
		t.Fatalf("not found updated user")
	}
	foundUpdatedUser := listWithUpdated.Users[0]
	if foundUpdatedUser.FirstName != "Вова" {
		t.Errorf("first name mismatch")
	}
}

func TestChangePassword(t *testing.T) {
	var err error
	servicesContext, finish := context.WithCancel(context.Background())
	services, err := StartServices(servicesContext, listenAddress, authorizationToken, testDatabaseProps)
	if err != nil {
		t.Fatalf("Can't start core_service: %v", err)
	}
	defer finish()

	createTestUsers(t, services)
	conn := createTestClientConnection(t)
	client := NewUserManagementClient(conn)
	ctx := createTestContext()

	adminSession, err := client.Authorize(ctx, &User{Email: "info@kremlin.org", Password: "qwerty"})
	if err != nil {
		t.Fatalf("can't authorize admin user: %v", err)
	}
	adminCtx := updateContextWithSession(ctx, adminSession)

	// 1 change password by Administrator
	usersList1, err := client.GetUsers(adminCtx, &UsersFilter{User: &User{Email: "vasya@lozkin.ru"}})
	if err != nil {
		t.Fatalf("[Test case 1]: Can't get existing user: %v", err)
	} else if len(usersList1.Users)!=1 {
		t.Fatalf("can't find existing user")
	}
	newUser, err := client.ResetUserPassword(adminCtx, &User{Id: usersList1.Users[0].Id, Password: "qwerty123"})
	if err != nil {
		t.Fatalf("[Test case 1]: Can't reset password by administrator: %v", err)
	}
	newUserSession, err := client.Authorize(ctx, &User{Email: "vasya@lozkin.ru", Password: newUser.Password})
	if err != nil {
		t.Fatalf("[Test case 1]: Can't authorize using new password: %v", err)
	}

	newUserContext := updateContextWithSession(ctx, newUserSession)
	// 2 change password by user itself
	_, err = client.ChangePassword(newUserContext, &User{Password: "qwerty456"})
	if err != nil {
		t.Fatalf("[Test case 2]: Can't change password by user: %v", err)
	}
	_, err = client.Authorize(ctx, &User{Email: "vasya@lozkin.ru", Password: "qwerty456"})
	if err != nil {
		t.Fatalf("[Test case 2]: Can't authorize using new password: %v", err)
	}
}
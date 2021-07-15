package core_service

import (
	"context"
	"crypto/sha256"
	"database/sql"
	_ "embed"
	"encoding/hex"
	"fmt"
	_ "google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"math/rand"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var Capabilities = map[Role][][2]string {
	Role_ROLE_UNAUTHORIZED: {
		{"UserManagement", "Authorize"},
		{"SubmissionsManagement", "ReceiveSubmissionsToGrade"},
		{"SubmissionsManagement", "UpdateGraderOutput"},
	},
	Role_ROLE_STUDENT: {
		{"UserManagement", "Authorize"},
		{"UserManagement", "GetProfile"},
		{"UserManagement", "ChangePassword"},
		{"CourseManagement", "GetCourses"},
		{"SubmissionsManagement", "ReceiveSubmissionsToGrade"},
		{"SubmissionsManagement", "UpdateGraderOutput"},
	},
}

type UserManagementService struct {
	Parent			*Services
	DB 				*sql.DB
}

func (service *UserManagementService) GenerateRandomPassword() (password string) {
	const alphabet = "01234567abcdef"
	password = ""
	for i := 0; i < 8; i++ {
		runeNum := rand.Int31n(int32(len(alphabet) - 1))
		rune := alphabet[runeNum]
		password += string(rune)
	}
	return password
}

func (service *UserManagementService) ResetUserPassword(ctx context.Context, user *User) (*User, error) {
	if user.Id == 0 || user.Password == "" {
		return nil, status.Errorf(codes.InvalidArgument, "user_id and password required")
	}
	newPass := "=" + service.GenerateRandomPassword()
	_, err := service.DB.Exec(`update users set password=$1 where id=$2`, newPass, user.Id)
	if err != nil {
		return nil, err
	}
	user.Password = newPass[1:]
	return user, nil
}

func (service *UserManagementService) ChangePassword(ctx context.Context, user *User) (*User, error) {
	if user.Password == "" {
		return nil, status.Errorf(codes.InvalidArgument, "no new password")
	}
	md, _ := metadata.FromIncomingContext(ctx)
	values := md.Get("session")
	if len(values) == 0 {
		return nil, status.Errorf(codes.Unauthenticated, "no session in metadata")
	}
	session := values[0]
	if session == "" {
		return nil, status.Errorf(codes.Unauthenticated, "session is empty")
	}
	currentUser, err := service.GetUserBySession(&Session{Cookie: session})
	if err != nil {
		return nil, status.Errorf(codes.Unauthenticated, "no associated user for session")
	}
	newPassword := MakePasswordHash(user.Password)
	query := `update users set password=$1 where id=$2`
	_, err = service.DB.Query(query, newPassword, currentUser.Id)
	return currentUser, err
}

func (service *UserManagementService) BatchCreateStudents(ctx context.Context, usersList *UsersList) (res *UsersList, err error) {
	res = usersList
	err = nil
	for index, user := range usersList.Users {
		user.Password = service.GenerateRandomPassword()
		user, err = service.CreateOrUpdateUser(ctx, user)
		if err != nil {
			err = fmt.Errorf("while creating '%s' '%s': %s'", user.LastName, user.FirstName, err.Error());
			return
		}
		user.DefaultRole = Role_ROLE_STUDENT
		_, err = service.SetUserDefaultRole(ctx, &UserRole{User: user, Role: user.DefaultRole})
		if err != nil {
			err = fmt.Errorf("while creating '%s' '%s': %s'", user.LastName, user.FirstName, err.Error());
			return
		}
		res.Users[index] = user
	}
	return
}

func (service *UserManagementService) BatchDeleteUsers(ctx context.Context, usersList *UsersList) (res *Nothing, err error) {
	for _, user := range usersList.Users {
		_, err = service.DeleteUser(ctx, user)
		if err != nil {
			return
		}
	}
	return &Nothing{}, nil
}

func (service *UserManagementService) DeleteUser(ctx context.Context, user *User) (res *Nothing, err error) {
	if user.Id==0 {
		return nil, status.Errorf(codes.InvalidArgument, "user id required")
	}
	_, err = service.DB.Exec(`delete from users where id=$1`, user.Id)
	if err != nil {
		return nil, err
	}
	return &Nothing{}, nil
}

func (service *UserManagementService) CreateOrUpdateUser(ctx context.Context, user *User) (res *User, err error) {
	if user.Id == 0 && (user.FirstName == "" || user.LastName == "") {
		return nil, status.Errorf(codes.InvalidArgument, "firstname and lastname are required")
	}
	res = new(User)
	if user.Id > 0 {
		// update existing user
		var midName, email, groupName sql.NullString
		userRow := service.DB.QueryRow(`select password, first_name, last_name, mid_name, email, group_name from users where id=$1`, user.Id)
		err = userRow.Scan(&res.Password, &res.FirstName, &res.LastName, &midName, &email, &groupName)
		if err != nil {
			return nil, err
		}
		if midName.Valid {
			res.MidName = midName.String
		}
		if email.Valid {
			res.Email = email.String
		}
		if groupName.Valid {
			res.GroupName = groupName.String
		}
	}
	fields := make([]string, 0, 10)
	values := make([]interface{}, 0, 10)
	if user.Password != "" && user.Id == 0 {
		// allows to set password only at initial registration stage
		// use ResetUserPassword (by Admin role) or ChangePassword (by any Role) to set password
		fields = append(fields, "password")
		values = append(values, "="+user.Password) // plain text on registration or teacher change
		res.Password = user.Password
	}
	if user.FirstName != "" {
		fields = append(fields, "first_name")
		values = append(values, user.FirstName)
		res.FirstName = user.FirstName
	}
	if user.LastName != "" {
		fields = append(fields, "last_name")
		values = append(values, user.LastName)
		res.LastName = user.LastName
	}
	if user.MidName != "" {
		fields = append(fields, "mid_name")
		values = append(values, user.MidName)
		res.MidName = user.MidName
	}
	if user.Email != "" {
		fields = append(fields, "email")
		values = append(values, user.Email)
		res.Email = user.Email
	}
	if user.GroupName != "" {
		fields = append(fields, "group_name")
		values = append(values, user.GroupName)
		res.GroupName = user.GroupName
	}

	sets := ""
	placeholders := ""
	for i := 0; i < len(fields); i++ {
		if i > 0 {
			sets += ", "
			placeholders += ","
		}
		sets += fmt.Sprintf("%s=$%d", fields[i], i+1)
		placeholders += fmt.Sprintf("$%d", i+1)
	}
	if user.Id > 0 {
		query := `update users set ` + sets + ` where id=` + strconv.Itoa(int(user.Id))
		_, err = service.DB.Exec(query, values...)
	} else {
		query := `insert into users(` + strings.Join(fields, ", ") + `) values (` + placeholders + `) returning id`
		err = service.DB.QueryRow(query, values...).Scan(&res.Id)
	}
	return res, err
}


func (service *UserManagementService) GetUsers(ctx context.Context, filter *UsersFilter) (*UsersList, error) {

	// Important note: this might work slow because we will not use SQL-based filtering

	if filter.Course != nil && filter.Course.Id > 0 {
		// todo
	} else {
		filter.Course = nil
	}

	query := `select id,first_name,last_name,mid_name,group_name,email,default_role,disabled from users`
	q, err := service.DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer q.Close()

	res := &UsersList{Users: make([]*User, 0, 1000)}
	for q.Next() {
		user := &User{}
		var midName sql.NullString
		var email sql.NullString
		var groupName sql.NullString
		var defaultRole sql.NullInt64
		err = q.Scan(&user.Id, &user.FirstName, &user.LastName, &midName, &groupName,
			&email, &defaultRole, &user.Disabled)
		if err != nil {
			return nil, err
		}
		if midName.Valid {
			user.MidName = midName.String
		}
		if email.Valid {
			user.Email = email.String
		}
		if groupName.Valid {
			user.GroupName = groupName.String
		}
		if defaultRole.Valid {
			user.DefaultRole = Role(defaultRole.Int64)
		}
		if filter.Course != nil {
			// todo: check for course+role match
		} else if filter.Role != Role_ROLE_ANY {
			if user.DefaultRole != filter.Role {
				continue // not matched by role
			}
		}
		if filter.User != nil {
			// check for name matching
			partial := filter.PartialStringMatch
			if !PartialStringMatch(partial, user.FirstName, filter.User.FirstName) {
				continue
			}
			if !PartialStringMatch(partial, user.LastName, filter.User.LastName) {
				continue
			}
			if !PartialStringMatch(partial, user.MidName, filter.User.MidName) {
				continue
			}
			if !PartialStringMatch(partial, user.Email, filter.User.Email) {
				continue
			}
			if !PartialStringMatch(partial, user.GroupName, filter.User.GroupName) {
				continue
			}
			if !filter.IncludeDisabled && user.Disabled {
				continue
			}
		}
		res.Users = append(res.Users, user)
	}
	return res, nil
}

func (service *UserManagementService) SetUserDefaultRole(ctx context.Context, arg *UserRole) (res *UserRole, err error) {
	if arg.User.Id == 0 && arg.User.Email == "" {
		return nil, status.Errorf(codes.InvalidArgument, "not valid user")
	}
	if arg.User.Id == 0 {
		q, err := service.DB.Query(`select id from users where email=$1`, arg.User.Email)
		if err != nil {
			return nil, err
		}
		defer q.Close()
		if q.Next() {
			q.Scan(&arg.User.Id)
		} else {
			return nil, status.Errorf(codes.NotFound, "user with email '%s' not found", arg.User.Email)
		}
	}
	_, err = service.DB.Exec(`update users set default_role=$1 where id=$2`, arg.Role, arg.User.Id)
	return arg, err
}



func (service *UserManagementService) Authorize(ctx context.Context, user *User) (sess *Session, err error) {
	if user.Id == 0 && user.Email == "" {
		return nil, status.Errorf(codes.InvalidArgument, "id or email not provided")
	}
	if user.Password == "" {
		return nil, status.Errorf(codes.InvalidArgument, "password not provided")
	}
	findByIdQuery := `select id, email, password from users where id=$1`
	findByEmailQuery := `select id, email, password from users where email=$1`
	var usersRows *sql.Rows
	if user.Id > 0 {
		usersRows, err = service.DB.Query(findByIdQuery, user.Id)
	} else {
		usersRows, err = service.DB.Query(findByEmailQuery, user.Email)
	}
	if err != nil {
		return nil, status.Errorf(codes.Internal, err.Error())
	}
	defer usersRows.Close()
	userFound := false
	userId := 0
	userEmail := ""
	userPassword := ""

	for usersRows.Next() {
		userFound = true
		err = usersRows.Scan(&userId, &userEmail, &userPassword)
		if err != nil {
			return nil, status.Errorf(codes.Internal, err.Error())
		}
	}

	if !userFound {
		return nil, status.Errorf(codes.NotFound, "user not found")
	}
	if userPassword == "" {
		return nil, status.Errorf(codes.PermissionDenied, "wrong password")
	}
	passwordMatch := false
	if user.Disabled {
		return nil, status.Errorf(codes.PermissionDenied, "user disabled")
	}
	if userPassword[0] == '=' {
		// plain text password
		passwordMatch = userPassword[1:] == user.Password
	} else {
		// sha512 hex digest
		hexString := MakePasswordHash(user.Password)
		passwordMatch = hexString == strings.ToLower(userPassword)
	}
	if !passwordMatch {
		return nil, status.Errorf(codes.PermissionDenied, "wrong password")
	}
	timestamp := time.Now().Unix()
	sessionKey := fmt.Sprintf(
		"Session: id = %d, email = %s, start = %d, random = %d",
		userId, userEmail, timestamp, rand.Int())
	sha256Hash := sha256.New()
	sha256Hash.Write([]byte(sessionKey))
	sha256Data := sha256Hash.Sum(nil)
	hexString := hex.EncodeToString(sha256Data)
	session := Session{
		Cookie: hexString,
		UserId: int64(userId),
		Start:  timestamp,
	}
	_, err = service.DB.Exec(
		`insert into sessions(cookie, users_id, start) values ($1, $2, $3)`,
		session.Cookie, session.UserId, time.Unix(timestamp, 0))
	if err != nil {
		return nil, status.Errorf(codes.Internal, err.Error())
	}
	return &session, nil
}

func (service *UserManagementService) CheckUserSession(ctx context.Context, requestMethod string) bool {
	md, _ := metadata.FromIncomingContext(ctx)
	pattern := regexp.MustCompile(`/([a-zA-Z0-9]+)\.([a-zA-Z0-9]+)/([a-zA-Z0-9]+)`)
	parts := pattern.FindStringSubmatch(requestMethod)
	subsystem := parts[2]
	method := parts[3]
	sessionLessAPIs := Capabilities[Role_ROLE_UNAUTHORIZED]
	for _, allowedApi := range sessionLessAPIs {
		allowedSubsystem := allowedApi[0]
		allowedMethod := allowedApi[1]
		if subsystem == allowedSubsystem && method == allowedMethod {
			return true
		}
	}
	values := md.Get("session")
	if len(values) == 0 {
		return false
	}
	session := values[0]
	if session == "" {
		return false
	}
	if subsystem != "Runs" { // this subsystem will manage user rights by itself
		user, err := service.GetUserBySession(&Session{Cookie: session})
		if err != nil {
			return false
		}
		if user.DefaultRole == Role_ROLE_ADMINISTRATOR {
			return true
		} else {
			foundCap := false
			caps := Capabilities[user.DefaultRole]
			for _, capEntry := range caps {
				capSubsystem := capEntry[0]
				capMethod := capEntry[1]
				if capSubsystem==subsystem && capMethod==method {
					foundCap = true
					break
				}
			}
			return foundCap
		}
	}
	return true
}


func (service *UserManagementService) GetUserBySession(session *Session) (user *User, err error) {
	if session.UserId == 0 {
		sessionResult, err := service.DB.Query(`select users_id from sessions where cookie=$1`,
			session.Cookie)
		if err != nil {
			return nil, err
		}
		defer sessionResult.Close()
		if sessionResult.Next() {
			err = sessionResult.Scan(&session.UserId)
			if err != nil {
				return nil, err
			}
		} else {
			return nil, fmt.Errorf("session not found")
		}
	}
	userResult, err := service.DB.Query(
		`select first_name, last_name, mid_name, password, email, group_name, default_role from users where id=$1`,
		session.UserId)
	if err != nil {
		return nil, err
	}
	defer userResult.Close()
	if userResult.Next() {
		result := &User{Id: session.UserId}
		var midName sql.NullString
		var groupName sql.NullString
		var defaultRole sql.NullInt64
		err = userResult.Scan(&result.FirstName, &result.LastName, &midName, &result.Password,
			&result.Email, &groupName, &defaultRole)
		if err != nil {
			return nil, err
		}
		if !strings.HasPrefix(result.Password, "=") {
			result.Password = "" // do not show passwords except registration plain text passwords
		} else {
			result.Password = result.Password[1:] // remove '=' plain text mark
		}
		if midName.Valid {
			result.MidName = midName.String
		}
		if groupName.Valid {
			result.GroupName = groupName.String
		}
		if defaultRole.Valid {
			result.DefaultRole = Role(defaultRole.Int64)
		}
		return result, nil
	} else {
		return nil, fmt.Errorf("no user found for session")
	}
}

func (service *UserManagementService) GetProfile(ctx context.Context, session *Session) (user *User, err error) {
	user, err = service.GetUserBySession(session)
	if err != nil {
		err = status.Errorf(codes.Internal, err.Error())
	}
	return
}

func (service UserManagementService) mustEmbedUnimplementedUserManagementServer() {
	panic("implement me")
}

func (service *UserManagementService) GetDefaultRole(user *User) (role Role, err error) {
	err = service.DB.QueryRow(`select default_role from users where id=$1`, user.Id).Scan(&role)
	return role, err
}


func NewUserManagementService(parent *Services) *UserManagementService {
	result := new(UserManagementService)
	result.Parent = parent
	result.DB = parent.DB
	return result
}

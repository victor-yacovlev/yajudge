package core_service

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/xml"
	"fmt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"gopkg.in/yaml.v2"
	"io"
	"io/fs"
	"os"
	"strings"
	"time"
)

type CourseDataCacheItem struct {
	Data			*CourseData
	LastModified	int64
	LastChecked		int64
	Error			error
}

type CourseManagementService struct {
	DB 			*sql.DB
	Parent		*Services
	Root		fs.FS
	Courses		map[string]CourseDataCacheItem
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

func (service *CourseManagementService) GetCourses(ctx context.Context, filter *CoursesFilter) (res *CoursesList, err error) {
	var enrollments []*Enrolment = nil
	if filter.User != nil && filter.User.Id > 0 {
		enrollments, err = service.GetUserEnrollments(filter.User)
		if err != nil {
			return nil, err
		}
	}
	allCourses, err := service.DB.Query(`select id,name,course_data,url_prefix from courses`)
	if err != nil {
		return nil, err
	}
	defer allCourses.Close()
	res = new(CoursesList)
	res.Courses = make([]*CoursesList_CourseListEntry, 0, 10)
	for allCourses.Next() {
		candidate := &Course{}
		candidate.CourseData = &CourseData{}
		err = allCourses.Scan(&candidate.Id, &candidate.Name, &candidate.CourseData.Id, &candidate.UrlPrefix)
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

func GuessContentType(fileName string) string {
	lastDotIndex := strings.LastIndex(fileName, ".")
	if lastDotIndex == -1 {
		return ""
	}
	suffix := fileName[lastDotIndex:]
	KnownTypes := map[string]string {
		".md": "text/markdown",
		".txt": "text/plain",
		".html": "text/html",
	}
	typee, found := KnownTypes[suffix]
	if !found {
		return ""
	}
	return typee
}

func GuessMarkdownTitle(textContent string) string {
	lines := strings.Split(textContent, "\n")
	for i:=0; i<len(lines) ; i++ {
		line := strings.TrimSpace(lines[i])
		if strings.HasPrefix(line, "#") && !strings.HasPrefix(line, "##") {
			title := strings.TrimSpace(line[1:])
			if len(title) > 0 {
				return title
			}
		}
	}
	return ""
}

func GuessTitle(textContent string, contentType string) string {
	if contentType == "text/markdown" {
		return GuessMarkdownTitle(textContent)
	}
	return ""
}



func ParseEjudgeStatementXML(xmlFile fs.File) (statement string, id string, err error) {
	xmlInfo, _ := xmlFile.Stat()
	xmlSize := xmlInfo.Size()
	buffer := make([]byte, xmlSize)
	_, err = xmlFile.Read(buffer)
	if err != nil {
		return "", "", err
	}
	dec := xml.NewDecoder(bytes.NewReader(buffer))
	dec.Strict = false
	var xmlPackage, xmlId string
	var textStart, textEnd int64
	textStart = -1
	textEnd = -1
	for {
		t, err := dec.Token()
		if err == io.EOF {
			break
		} else if err != nil {
			return "", "", err
		}
		if se, ok := t.(xml.StartElement); ok {
			if se.Name.Local == "problem" {
				for _, attr := range se.Attr {
					if attr.Name.Local == "id" {
						xmlId = attr.Value
					} else if attr.Name.Local == "package" {
						xmlPackage = attr.Value
					}
				}
			} else if se.Name.Local == "description" {
				textStart = dec.InputOffset()
			}
		}
		if se, ok := t.(xml.EndElement); ok {
			if se.Name.Local == "description" {
				textEnd = dec.InputOffset() - int64(len(se.Name.Local)+3)
			}
		}
	}
	id = strings.Replace(xmlPackage, ".", "/", -1) + "/" + xmlId
	if textStart != -1 && textEnd != -1 {
		statementData := buffer[textStart:textEnd]
		statement = string(statementData)
	}
	_, _ = textStart, textEnd
	return
}


func (service *CourseManagementService) GetEjudgeProblem(problemPrefix string) (data *ProblemData, timestamp int64, err error) {
	// 1. Get statement
	statementFileName := problemPrefix + "/statement.xml"
	statementFileInfo, err := fs.Stat(service.Root, statementFileName)
	if err != nil {
		return nil, 0, fmt.Errorf("while accessing '%s': %v", statementFileName, err)
	}
	if statementFileInfo.ModTime().Unix() > timestamp {
		timestamp = statementFileInfo.ModTime().Unix()
	}
	statementFile, err := service.Root.Open(statementFileName);
	if err != nil {
		return nil, 0, fmt.Errorf("can't open '%s': %v", statementFileName, err)
	}
	data = &ProblemData{}
	data.StatementText, data.UniqueId, err = ParseEjudgeStatementXML(statementFile)
	if err != nil {
		return nil, 0, fmt.Errorf("while parsing '%s': %v", statementFileName, err)
	}
	// 2. Get config
	// TODO implement me
	return
}

func (service *CourseManagementService) GetProblemFromYaml(problemPrefix string) (data *ProblemData, timestamp int64, err error) {
	return
}

func (service *CourseManagementService) GetLessonProblems(prefix string, parentDataMap map[string]interface{}) ([]*ProblemData, int64, error) {
	problemsValue := parentDataMap["problems"]
	if problemsValue == nil {
		return make([]*ProblemData, 0), 0, nil
	}
	problemIds := problemsValue.([]interface{})
	result := make([]*ProblemData, 0, len(problemIds))
	var lastModified int64 = 0
	for _, problemObject := range problemIds {
		problemId, isString := problemObject.(string)
		if !isString {
			continue
		}
		problemPrefix := prefix + "/" + problemId
		data := &ProblemData{}
		yamlFileName := problemPrefix + "/problem.yaml"
		yamlFileInfo, err := fs.Stat(service.Root, yamlFileName)
		noYamlFile := false
		if err != nil {
			noYamlFile = true
			err = nil
		} else if err == nil && yamlFileInfo.ModTime().Unix() > lastModified {
			lastModified = yamlFileInfo.ModTime().Unix()
		}
		var problemLastModified int64
		var problemErr error
		if noYamlFile {
			data, problemLastModified, problemErr = service.GetEjudgeProblem(problemPrefix)
		} else {
			data, problemLastModified, problemErr = service.GetProblemFromYaml(problemPrefix)
		}
		if problemErr != nil {
			return nil, 0, problemErr
		}
		data.Id = problemId
		if problemLastModified > lastModified {
			lastModified = problemLastModified
		}
		result = append(result, data)
	}
	return result, lastModified, nil
}

func (service *CourseManagementService) GetLessonReadings(prefix string, parentDataMap map[string]interface{}) ([]*TextReading, int64, error) {
	readingsValue := parentDataMap["readings"]
	if readingsValue == nil {
		return make([]*TextReading, 0), 0, nil
	}
	readingIds := readingsValue.([]interface{})
	result := make([]*TextReading, 0, len(readingIds))
	var lastModified int64 = 0
	for _, readingObject := range readingIds {
		readingId, isString := readingObject.(string)
		if !isString {
			continue
		}
		readingPrefix := prefix + "/" + readingId
		readingFileInfo, err := fs.Stat(service.Root, readingPrefix)
		if err != nil {
			return nil, 0, fmt.Errorf("while accessing '%s': %v", readingPrefix, err)
		}
		data := &TextReading{}
		var dataFileName string
		if readingFileInfo.IsDir() {
			data.Id = readingId
			yamlFileName := readingPrefix + "/reading.yaml"
			yamlFileInfo, err := fs.Stat(service.Root, yamlFileName)
			if err != nil {
				return nil, 0, fmt.Errorf("while accessing '%s': %v", yamlFileName, err)
			}
			if yamlFileInfo.ModTime().Unix() > lastModified {
				lastModified = yamlFileInfo.ModTime().Unix()
			}
			lessonYamlContent, err := fs.ReadFile(service.Root, yamlFileName)
			if err != nil {
				return nil, 0, fmt.Errorf("while reading '%s': %v", yamlFileName, err)
			}
			dataMap := make(map[string]interface{})
			err = yaml.Unmarshal(lessonYamlContent, &dataMap)
			if err != nil {
				return nil, 0, fmt.Errorf("while reading '%s': %v", yamlFileName, err)
			}
			if dataMap["title"] != nil {
				data.Title = dataMap["title"].(string)
			}
			if dataMap["content_type"] != nil {
				data.ContentType = dataMap["content_type"].(string)
			}
			if dataMap["data"] == nil {
				return nil, 0, fmt.Errorf("no data file specified in '%s'", yamlFileName)
			}
			dataFileName = readingPrefix + "/" + dataMap["data"].(string)
		} else {
			data.Id = readingId
			dotPos := strings.LastIndex(data.Id, ".")
			if dotPos != -1 {
				data.Id = data.Id[0:dotPos]
			}
			dataFileName = readingPrefix
		}
		dataFileInfo, err := fs.Stat(service.Root, dataFileName)
		if err != nil {
			return nil, 0, fmt.Errorf("while accessing '%s': %v", dataFileName, err)
		}
		if dataFileInfo.ModTime().Unix() > lastModified {
			lastModified = dataFileInfo.ModTime().Unix()
		}
		dataFileContent, err := fs.ReadFile(service.Root, dataFileName)
		if err != nil {
			return nil, 0, fmt.Errorf("while reading '%s': %v", dataFileName, err)
		}
		if len(data.ContentType) == 0 {
			data.ContentType = GuessContentType(dataFileName)
		}
		if data.ContentType == "" {
			return nil, 0, fmt.Errorf("unknown content type for '%s'", dataFileName)
		}
		if strings.HasPrefix(data.ContentType, "text/") {
			data.Data = string(dataFileContent)
		} else {
			// TODO implement me
			return nil, 0, fmt.Errorf("binary text reading types not supported yet")
		}
		if data.Title == "" {
			data.Title = GuessTitle(data.Data, data.ContentType)
		}
		if data.Title == "" {
			return nil, 0, fmt.Errorf("no title for reading '%s'", dataFileName)
		}
		result = append(result, data)
	}
	return result, lastModified, nil
}

func ParseRelativeDate(src interface{}, previous int64) int64 {
	// TODO implement me
	return previous + 0
}

func (service *CourseManagementService) GetSectionLessons(prefix string, parentDataMap map[string]interface{}) ([]*Lesson, int64, error) {
	lessonsValue := parentDataMap["lessons"]
	if lessonsValue == nil {
		return make([]*Lesson, 0), 0, nil
	}
	lessonIds := lessonsValue.([]interface{})
	result := make([]*Lesson, 0, len(lessonIds))
	var lastModified int64 = 0
	var openDate int64 = 0
	var softDeadline int64 = 0
	var hardDeadline int64 = 0
	for _, lessonObject := range lessonIds {
		lessonId, isString := lessonObject.(string)
		if !isString {
			continue
		}
		lessonPrefix := prefix + "/" + lessonId
		yamlFileName := lessonPrefix + "/lesson.yaml"
		yamlFileInfo, err := fs.Stat(service.Root, yamlFileName)
		if err != nil {
			return nil, 0, fmt.Errorf("while accessing '%s': %v", yamlFileName, err)
		}
		if yamlFileInfo.ModTime().Unix() > lastModified {
			lastModified = yamlFileInfo.ModTime().Unix()
		}
		lessonYamlContent, err := fs.ReadFile(service.Root, yamlFileName)
		if err != nil {
			return nil, 0, fmt.Errorf("while reading '%s': %v", yamlFileName, err)
		}
		dataMap := make(map[string]interface{})
		err = yaml.Unmarshal(lessonYamlContent, &dataMap)
		if err != nil {
			return nil, 0, fmt.Errorf("while reading '%s': %v", yamlFileName, err)
		}
		data := &Lesson{Id: lessonId}
		if dataMap["name"] != nil {
			data.Name = dataMap["name"].(string)
		} else {
			return nil, 0, fmt.Errorf("lesson '%s' has no name", yamlFileName)
		}
		if dataMap["description"] != nil {
			data.Description = dataMap["description"].(string)
		}
		openDate = ParseRelativeDate(dataMap["open_date"], openDate)
		softDeadline = ParseRelativeDate(dataMap["soft_deadline"], softDeadline)
		hardDeadline = ParseRelativeDate(dataMap["hard_deadline"], hardDeadline)
		data.OpenDate = openDate
		data.SoftDeadline = softDeadline
		data.HardDeadline = hardDeadline
		var readingsLastModified int64
		data.Readings, readingsLastModified, err = service.GetLessonReadings(lessonPrefix, dataMap)
		if err != nil {
			return nil, 0, err
		}
		if readingsLastModified > lastModified {
			lastModified = readingsLastModified
		}
		problems, problemsLastModified, problemsErr := service.GetLessonProblems(lessonPrefix, dataMap)
		if problemsErr != nil {
			return nil, 0, problemsErr
		}
		data.Problems = problems
		if data.Problems == nil {
			panic("data problems is nil after no error catched")
		}
		if problemsLastModified > lastModified {
			lastModified = problemsLastModified
		}
		result = append(result, data)
	}
	return result, lastModified, nil
}

func (service *CourseManagementService) GetCourseSections(prefix string,
	parentDataMap map[string]interface{}) ([]*Section, int64, error) {
	sectionsValue := parentDataMap["sections"]
	if sectionsValue == nil {
		return make([]*Section, 0), 0, nil
	}
	sectionIds := sectionsValue.([]interface{})
	result := make([]*Section, 0, len(sectionIds))
	var lastModified int64 = 0
	var openDate int64 = 0
	var softDeadline int64 = 0
	var hardDeadline int64 = 0
	for _, sectionObject := range sectionIds {
		sectionId, isString := sectionObject.(string)
		if !isString {
			continue
		}
		sectionPrefix := prefix + "/" + sectionId
		yamlFileName := sectionPrefix + "/section.yaml"
		yamlFileInfo, err := fs.Stat(service.Root, yamlFileName)
		if err != nil {
			return nil, 0, fmt.Errorf("while accessing '%s': %v", yamlFileName, err)
		}
		if yamlFileInfo.ModTime().Unix() > lastModified {
			lastModified = yamlFileInfo.ModTime().Unix()
		}
		sectionYamlContent, err := fs.ReadFile(service.Root, yamlFileName)
		if err != nil {
			return nil, 0, fmt.Errorf("while reading '%s': %v", yamlFileName, err)
		}
		dataMap := make(map[string]interface{})
		err = yaml.Unmarshal(sectionYamlContent, &dataMap)
		if err != nil {
			return nil, 0, fmt.Errorf("while reading '%s': %v", yamlFileName, err)
		}
		data := &Section{Id: sectionId}
		if dataMap["name"] != nil {
			data.Name = dataMap["name"].(string)
		} else {
			data.Name = ""  // unnamed top-level section
		}
		if dataMap["description"] != nil {
			data.Description = dataMap["description"].(string)
		}
		openDate = ParseRelativeDate(dataMap["open_date"], openDate)
		softDeadline = ParseRelativeDate(dataMap["soft_deadline"], softDeadline)
		hardDeadline = ParseRelativeDate(dataMap["hard_deadline"], hardDeadline)
		data.OpenDate = openDate
		data.SoftDeadline = softDeadline
		data.HardDeadline = hardDeadline
		var lessonsModified int64
		data.Lessons, lessonsModified, err = service.GetSectionLessons(sectionPrefix, dataMap)
		if err != nil {
			return nil, 0, err
		}
		if lessonsModified > lastModified {
			lastModified = lessonsModified
		}
		result = append(result, data)
	}
	return result, lastModified, nil
}

func (service *CourseManagementService) LoadCourseIntoCache(courseId string) {
	yamlFileName := courseId + "/course.yaml"
	cache := CourseDataCacheItem{}
	serviceYamlInfo, err := fs.Stat(service.Root, yamlFileName)
	if err != nil {
		cache.Error = err
		service.Courses[courseId] = cache
		return
	}
	var lastModified int64 = serviceYamlInfo.ModTime().Unix()

	serviceYamlContent, err := fs.ReadFile(service.Root, yamlFileName)
	if err != nil {
		cache.Error = fmt.Errorf("while reading '%s': %v", yamlFileName, err)
		return
	}
	dataMap := make(map[string]interface{})
	err = yaml.Unmarshal(serviceYamlContent, &dataMap)
	if err != nil {
		cache.Error = fmt.Errorf("while reading '%s': %v", yamlFileName, err)
		return
	}
	data := CourseData{}
	data.Id = courseId
	if dataMap["description"] != nil {
		data.Description = dataMap["description"].(string)
	}
	var sectionsLastModified int64
	data.Sections, sectionsLastModified, err = service.GetCourseSections(courseId, dataMap)
	if err != nil {
		cache.Error = err
	}
	if sectionsLastModified > lastModified {
		lastModified = sectionsLastModified
	}
	cache.Data = &data
	cache.LastModified = lastModified
	cache.LastChecked = time.Now().Unix()
	service.Courses[courseId] = cache
}

func (service *CourseManagementService) GetCoursePublicContent(ctx context.Context, request *CourseContentRequest) (response *CourseContentResponse, err error) {
	courseId := request.CourseDataId
	if courseId == "" {
		return nil, status.Errorf(codes.InvalidArgument, "course data id required");
	}
	const ReloadCourseInterval = 15
	now := time.Now().Unix()
	cached, inCache := service.Courses[courseId]
	if !inCache {
		service.LoadCourseIntoCache(courseId)
		cached, _ = service.Courses[courseId]
	}
	if cached.LastChecked >= (now + ReloadCourseInterval) || cached.Error != nil {
		service.LoadCourseIntoCache(courseId)
		cached, _ = service.Courses[courseId]
	}
	if cached.Error != nil {
		return nil, cached.Error
	}
	if request.CachedTimestamp >= cached.LastModified {
		return &CourseContentResponse{CourseDataId: request.CourseDataId, Status: CourseContentStatus_NOT_CHANGED}, nil
	}
	return &CourseContentResponse{
		Status: CourseContentStatus_HAS_DATA,
		CourseDataId: courseId,
		Data: cached.Data,
		LastModified: cached.LastModified,
	}, nil
}


func (service CourseManagementService) mustEmbedUnimplementedCourseManagementServer() {
	panic("implement me")
}

func NewCourseManagementService(parent *Services, coursesRoot string) *CourseManagementService {
	root := os.DirFS(coursesRoot)
	return &CourseManagementService{
		DB: parent.DB,
		Parent: parent,
		Root: root,
		Courses: make(map[string]CourseDataCacheItem),
	}
}

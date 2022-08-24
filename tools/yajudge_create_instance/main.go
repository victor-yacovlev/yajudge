package main

import (
	"crypto/sha512"
	"database/sql"
	_ "embed"
	"encoding/base64"
	"flag"
	"fmt"
	"github.com/ghodss/yaml"
	_ "github.com/lib/pq"
	"io"
	"log"
	"math/rand"
	"os"
	"os/exec"
	"os/user"
	"path"
	"strconv"
	"strings"
	"time"
)

var masterServices = []string{
	"users",
	"content",
	"courses",
	"sessions",
	"submissions",
	"deadlines",
	"review",
	"progress",
}

//go:embed yajudge-db-schema.sql
var YajudgeDBSchemaSQL string

func main() {
	force := flag.Bool("force", false, "try to run without root privileges")
	userName := flag.String("U", "yajudge", "service user name")
	groupName := flag.String("G", "yajudge", "service group name")
	hostName := flag.String("H", "", "fully qualified host name")
	noCreateDb := flag.Bool("no-create-db", false, "skip database creation")
	noInitializeDb := flag.Bool("no-initialize-db", false, "skip database initialization")
	noCreateNginx := flag.Bool("no-create-nginx-conf", false, "skip nginx configuration creation")
	disableGrader := flag.Bool("disable-grader", false, "disable grader for this configuration")
	graderOnly := flag.Bool("grader-only", false, "configure only grader but not master services")
	adminLogin := flag.String("L", "", "admin user login name")
	adminPassword := flag.String("P", "", "admin user initial password")
	flag.Parse()
	confName := flag.Arg(0)
	if confName == "" {
		println("Required instance name to create new yajudge configuration")
		os.Exit(1)
	}
	yajudgeUser, err := user.Lookup(*userName)
	if err != nil {
		println("No %s system user created, run 'yajudge-post-install' as root first", userName)
		os.Exit(1)
	}
	if *graderOnly && *disableGrader {
		println("Conflicting flags '--disable-grader' and '--grader-only'")
		os.Exit(1)
	}
	if !*graderOnly && (*adminLogin == "" || *adminPassword == "") {
		println("Must specify admin login and initial temporary (not secure) password")
		println("using '-L ADMIN_LOGIN' and '-P ADMIN_INITIAL_PASSWORD' flags")
		os.Exit(1)
	}
	skipRootPermissions := *force || *noCreateDb && *noCreateNginx || *graderOnly
	if !skipRootPermissions && os.Getuid() != 0 {
		println("Must have root permissions to:")
		println("  1) temporary log in as yajudge system user for PostgreSQL peer authentication")
		println("  2) create nginx site configuration")
		println("To match (1) requirement you also can run as yajudge user but not root")
		println("or create database 'yajudge_" + confName + "' by yourself and pass '--no-create-db' flag.")
		println("To match (2) requirement you also can skip creating nginx configuration")
		println("by passing '--no-create-nginx-conf' flag.")
		os.Exit(1)
	}
	yajudgeHome, err := resolveYajudgeRootDir()
	if err != nil {
		log.Fatalf("cant resolve yajudge home directory: %v", err)
	}
	if *hostName == "" && !*graderOnly {
		println("Must specify fully-qualified web host name using '-H NAME' parameter")
		os.Exit(1)
	}
	if !*noCreateDb && !*graderOnly {
		CreatePostgreSQLDatabase("yajudge_"+confName, yajudgeUser)
	}
	if !*noInitializeDb && !*graderOnly {
		dbPassword := ReadTextConfig(yajudgeHome, "database-password.txt")
		dbUser := "yajudge"
		dbName := "yajudge_" + confName
		InitializeDatabase(dbUser, dbPassword, dbName)
	}
	if !*graderOnly {
		dbPassword := ReadTextConfig(yajudgeHome, "database-password.txt")
		dbUser := "yajudge"
		dbName := "yajudge_" + confName
		CreateAdminUser(dbUser, dbPassword, dbName, *adminLogin, *adminPassword)
	}
	yajudgeGroup, err := user.LookupGroup(*groupName)
	if err != nil {
		log.Fatalf("yajudge group not created: %v", err)
	}
	httpPort := 0
	if !*graderOnly {
		webServerConf := ParseWebServerConf(yajudgeHome)
		httpPort = webServerConf.Listen.HttpPort
	}
	CreateConfigFiles(confName, yajudgeUser, yajudgeGroup, yajudgeHome,
		*hostName, httpPort, !*noCreateNginx, !*disableGrader, *graderOnly)
	println("Created configuration in " + yajudgeHome + "/conf/" + confName)
	println("Now you can start it using 'yajudge-control' command.")
	println("Important! Administrator password stored in insecure way, so change it first after login.")
	if !*disableGrader {
		println("To complete grader setup you must install local Linux distribution in " + yajudgeHome + "/system.")
		println("See README.md for detailed information.")
	}
}

type ListenConf struct {
	HttpPort    int    `json:"http_port" yaml:"http_port"`
	BindAddress string `json:"bind_address" yaml:"bind_address"`
}

type WebServerConf struct {
	Listen ListenConf `json:"listen" yaml:"listen"`
}

func ParseWebServerConf(yajudgeHome string) *WebServerConf {
	confPath := path.Join(yajudgeHome, "conf", "webserver.yaml")
	confData, err := os.ReadFile(confPath)
	if err != nil {
		log.Fatalf("cant read %s: %v", confPath, err)
	}
	var result WebServerConf
	if err := yaml.Unmarshal(confData, &result); err != nil {
		log.Fatalf("cant parse %s: %v", confPath, err)
	}
	return &result
}

func CreatePostgreSQLDatabase(dbName string, yajudgeUser *user.User) {
	sqlStatement := "create database $dbName;\n"
	sqlStatement = strings.ReplaceAll(sqlStatement, "$dbName", dbName)
	var command string
	commandArgs := make([]string, 0, 10)
	yajudgeUid, _ := strconv.Atoi(yajudgeUser.Uid)
	if os.Getuid() == 0 {
		command = "sudo"
		commandArgs = append(commandArgs, "-u", yajudgeUser.Username, "psql", "postgres")
	} else if os.Getuid() == yajudgeUid {
		command = "psql"
		commandArgs = append(commandArgs, "postgres")
	}
	cmd := exec.Command(command, commandArgs...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	if err := cmd.Start(); err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	if _, err := io.WriteString(stdin, sqlStatement); err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	stdin.Close()
	stderrContent, err := io.ReadAll(stderr)
	cmd.Wait()
	if err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	stdoutLines := strings.Split(string(stderrContent), "\n")
	for _, line := range stdoutLines {
		if strings.Contains(line, "ERROR") {
			log.Print(line)
		}
	}
}

func InitializeDatabase(userName, password, dbName string) {
	connString := fmt.Sprintf("postgres://%s:%s@localhost/%s?sslmode=disable", userName, password, dbName)
	db, err := sql.Open("postgres", connString)
	if err != nil {
		log.Fatalf("cant estabish dababase connection to %s: %v", dbName, err)
	}
	sqlStatements := YajudgeDBSchemaSQL
	_, err = db.Exec(sqlStatements)
	if err != nil {
		log.Printf("Error executing SQL statements while initializing database: %v", err)
	}
	db.Close()
}

func CreateAdminUser(dbUser, dbPassword, dbName string, adminLogin, adminPassword string) {
	connString := fmt.Sprintf("postgres://%s:%s@localhost/%s?sslmode=disable", dbUser, dbPassword, dbName)
	db, err := sql.Open("postgres", connString)
	if err != nil {
		log.Fatalf("cant estabish dababase connection to %s: %v", dbName, err)
	}
	sqlStatement := `insert into users(login,password,default_role) values ($1,$2,$3);`
	_, err = db.Exec(sqlStatement, adminLogin, "="+adminPassword, 6)
	if err != nil {
		log.Fatalf("cant create administrator account: %v", err)
	}
	db.Close()
}

func ReadTextConfig(yajudgeHome, relativeName string) string {
	passwordFileName := path.Join(yajudgeHome, "conf", relativeName)
	passwordFile, err := os.OpenFile(passwordFileName, os.O_RDONLY, 0)
	if err != nil {
		log.Fatalf("cant open database password file %s: %v", passwordFileName, err)
	}
	fileContent, err := io.ReadAll(passwordFile)
	if err != nil {
		log.Fatalf("cant read password file %s: %v", passwordFileName, err)
	}
	password := string(fileContent)
	password = strings.TrimSpace(password)
	return password
}

func findUserAndGroup(userName, groupName string) (*user.User, *user.Group, bool) {
	yajudgeUser, err := user.Lookup(userName)
	if err != nil {
		switch err.(type) {
		case user.UnknownUserError:
			return nil, nil, false
		default:
			log.Fatalf("cant find user %s: %v", userName, err)
		}
	}
	yajudgeGroup, err := user.LookupGroup(groupName)
	if err != nil {
		switch err.(type) {
		case user.UnknownGroupError:
			return nil, nil, false
		default:
			log.Fatalf("cant find group %s: %v", groupName, err)
		}
	}
	return yajudgeUser, yajudgeGroup, true
}

func GeneratePrivateToken() string {
	rand.Seed(time.Now().Unix())
	randData := ""
	for i := 0; i < 1000; i++ {
		randUint := rand.Uint64()
		randData += strconv.FormatUint(randUint, 16)
	}
	hasher := sha512.New()
	hashValue := hasher.Sum([]byte(randData))
	hashB64 := base64.StdEncoding.EncodeToString(hashValue)
	return hashB64
}

func CreateConfigFiles(confName string, yajudgeUser *user.User, yajudgeGroup *user.Group,
	yajudgeHome string, hostName string, httpPort int,
	enableNginx, enableGrader, graderOnly bool,
) {
	uid, _ := strconv.Atoi(yajudgeUser.Uid)
	gid, _ := strconv.Atoi(yajudgeGroup.Gid)
	sourceConfDir := path.Join(yajudgeHome, "conf")
	targetConfDir := path.Join(yajudgeHome, "conf", confName)
	if err := os.MkdirAll(targetConfDir, 0o775); err != nil {
		log.Fatalf("cant create %s: %v", targetConfDir, err)
	}
	if err := os.Chown(targetConfDir, uid, gid); err != nil {
		log.Fatalf("cant chown %s to %v:%v: %v", targetConfDir, uid, gid, err)
	}
	if err := os.Chmod(targetConfDir, os.FileMode(0o775)); err != nil {
		log.Fatalf("cant chmod %s to 0755: %v", targetConfDir, err)
	}
	var enableGraderValue string
	var masterServicesValue string
	if enableGrader {
		enableGraderValue = "true"
	} else {
		enableGraderValue = "false"
	}
	if graderOnly {
		masterServicesValue = ""
	} else {
		masterServicesValue = strings.Join(masterServices, " ")
	}
	substitutions := map[string]string{
		"YAJUDGE_HOME":    yajudgeHome,
		"CONFIG_NAME":     confName,
		"HOST_NAME":       hostName,
		"HTTP_PORT":       strconv.Itoa(httpPort),
		"ENABLE_GRADER":   enableGraderValue,
		"MASTER_SERVICES": masterServicesValue,
	}
	entries, err := os.ReadDir(sourceConfDir)
	if err != nil {
		log.Fatalf("cant read directory %s contents: %v", sourceConfDir, err)
	}
	for _, entry := range entries {
		if !strings.Contains(entry.Name(), "@") || strings.Contains(entry.Name(), "nginx") {
			continue
		}
		targetName := entry.Name()
		targetName = strings.ReplaceAll(targetName, "@", "")
		targetName = strings.ReplaceAll(targetName, ".in", "")
		InstallConfigFile(
			path.Join(sourceConfDir, entry.Name()),
			path.Join(targetConfDir, targetName),
			uid, gid, 0o664,
			substitutions,
		)
	}
	if enableNginx {
		nginxSitesAvailable := "/etc/nginx/sites-available"
		nginxSitesEnabled := "/etc/nginx/sites-enabled"
		if err := os.MkdirAll(nginxSitesAvailable, 0o755); err != nil {
			log.Fatalf("cant create directory %s: %v", nginxSitesAvailable, err)
		}
		if err := os.MkdirAll(nginxSitesEnabled, 0o755); err != nil {
			log.Fatalf("cant create directory %s: %v", nginxSitesEnabled, err)
		}
		InstallConfigFile(
			path.Join(sourceConfDir, "nginx@.in.conf"),
			path.Join(nginxSitesAvailable, fmt.Sprintf("yajudge-%s.conf", confName)),
			0, 0, 0o644,
			substitutions,
		)
		os.Symlink(
			fmt.Sprintf("../sites-available/yajudge-%s.conf", confName),
			path.Join(nginxSitesEnabled, fmt.Sprintf("yajudge-%s.conf", confName)),
		)
	}
	CreatePlainText(
		GeneratePrivateToken(),
		path.Join(targetConfDir, "private-token.txt"),
		uid, gid, 0o660,
	)
}

func CreatePlainText(content, target string, uid, gid int, perms uint32) {
	if _, err := os.Stat(target); err == nil {
		log.Printf("config file %s exists, skipped", target)
		return
	}
	targetFile, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, os.FileMode(perms))
	if err != nil {
		log.Fatalf("cant create %s: %v", target, err)
	}
	if _, err := io.WriteString(targetFile, content); err != nil {
		log.Fatalf("cant write %s: %v", target, err)
	}
	targetFile.Close()
	if err := os.Chown(target, uid, gid); err != nil {
		log.Fatalf("cant chown created file to %v:%v : %v", uid, gid, err)
	}
	if err := os.Chmod(target, os.FileMode(perms)); err != nil {
		log.Fatalf("cant chmod created file to 0%o : %v", perms, err)
	}
}

func InstallConfigFile(source, target string, uid, gid int, perms uint32, substitutions map[string]string) {
	sourceFile, err := os.OpenFile(source, os.O_RDONLY, 0)
	if err != nil {
		log.Fatalf("cant open %s: %v", source, err)
	}
	content, err := io.ReadAll(sourceFile)
	if err != nil {
		log.Fatalf("cant read %s: %v", source, err)
	}
	sourceFile.Close()
	contentString := string(content)
	for k, v := range substitutions {
		contentString = strings.ReplaceAll(contentString, "@"+k, v)
	}
	if _, err := os.Stat(target); err == nil {
		log.Printf("config file %s exists, skipped", target)
		return
	}
	targetFile, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, os.FileMode(perms))
	if err != nil {
		log.Fatalf("cant create %s: %v", target, err)
	}
	if _, err := io.WriteString(targetFile, contentString); err != nil {
		log.Fatalf("cant write %s: %v", target, err)
	}
	targetFile.Close()
	if err := os.Chown(target, uid, gid); err != nil {
		log.Fatalf("cant chown created file to %v:%v : %v", uid, gid, err)
	}
	if err := os.Chmod(target, os.FileMode(perms)); err != nil {
		log.Fatalf("cant chmod created file to 0%o : %v", perms, err)
	}
}

func resolveYajudgeRootDir() (string, error) {
	serverExecutable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("cant resolve yajudge directory: %v", err)
	}
	if stat, _ := os.Lstat(serverExecutable); stat.Mode()&os.ModeSymlink != 0 {
		serverExecutable, _ = os.Readlink(serverExecutable)
	}
	executableDir := path.Dir(serverExecutable)
	if !path.IsAbs(executableDir) {
		cwd, _ := os.Getwd()
		executableDir = path.Clean(path.Join(cwd, executableDir))
	}
	executableDirName := path.Base(executableDir)
	var suffix string
	if executableDirName == "bin" || executableDirName == "sbin" {
		suffix = ".."
	} else {
		suffix = "../.."
	}
	parentDir := path.Clean(path.Join(executableDir, suffix))
	return parentDir, nil
}

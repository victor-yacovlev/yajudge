package main

import (
	"crypto/sha512"
	"encoding/base64"
	"flag"
	"fmt"
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

const (
	PostgreSQLSystemUser = "postgres"
)

func main() {
	force := flag.Bool("force", false, "try to run without root privileges")
	userName := flag.String("U", "yajudge", "service user name")
	groupName := flag.String("G", "yajudge", "service group name")
	httpPort := flag.Int("W", 1080, "http web port number")
	postgresPassword := flag.String("P", "yajudge", "PostgreSQL password for yajudge role")
	flag.Parse()
	if !*force && os.Getuid() != 0 {
		println("Must be root user to run this post-install script")
		os.Exit(1)
	}
	CreateSystemUserAndGroup(*userName, *groupName)
	CreatePostgreSQLUser("yajudge", *postgresPassword)
	yajudgeUser, err := user.Lookup(*userName)
	if err != nil {
		log.Fatalf("yajudge user not created: %v", err)
	}
	yajudgeGroup, err := user.LookupGroup(*groupName)
	if err != nil {
		log.Fatalf("yajudge group not created: %v", err)
	}
	yajudgeHome, err := resolveYajudgeRootDir()
	if err != nil {
		log.Fatalf("cant resolve yajudge home directory: %v", err)
	}
	CreateInitialConfig(yajudgeUser, yajudgeGroup, yajudgeHome, *httpPort)
	println("Created initial system configuration.")
	println("Now you can start or enable unit 'yajudge.service' using 'systemctl' command.")
}

func CreateSystemUserAndGroup(userName, homeDir string) {
	cmd := exec.Command("useradd", "-rmU", "/usr/sbin/nologin", "-d", homeDir, userName)
	cmd.Start()
	cmd.Wait()
}

func CreatePostgreSQLUser(userName, password string) {
	sqlStatement := "create role @name with password '@password' nosuperuser createdb inherit login;\n"
	sqlStatement = strings.ReplaceAll(sqlStatement, "@name", userName)
	sqlStatement = strings.ReplaceAll(sqlStatement, "@password", password)
	cmd := exec.Command("sudo", "-u", PostgreSQLSystemUser, "psql")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	if err := cmd.Start(); err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	if _, err := io.WriteString(stdin, sqlStatement); err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	stdin.Close()
	cmd.Wait()
	stdoutContent, err := io.ReadAll(stdout)
	if err != nil {
		log.Fatalf("cant execute sql statements: %v", err)
	}
	stdoutLines := strings.Split(string(stdoutContent), "\n")
	for _, line := range stdoutLines {
		if strings.Contains(line, "ERROR") {
			log.Print(line)
		}
	}
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

func CreateInitialConfig(yajudgeUser *user.User, yajudgeGroup *user.Group, yajudgeHome string, httpPort int) {
	uid, _ := strconv.Atoi(yajudgeUser.Uid)
	gid, _ := strconv.Atoi(yajudgeGroup.Gid)
	confDir := path.Join(yajudgeHome, "conf")
	systemdDir := path.Join(yajudgeHome, "systemd")
	etcSystemdSystem := "/etc/systemd/system"
	if err := os.MkdirAll(confDir, 0o775); err != nil {
		log.Fatalf("cant create %s: %v", confDir, err)
	}
	if err := os.Chown(confDir, uid, gid); err != nil {
		log.Fatalf("cant chown %s to %v:%v: %v", confDir, uid, gid, err)
	}
	InstallConfigFile(
		path.Join(confDir, "webserver.in.yaml"),
		path.Join(confDir, "webserver.yaml"),
		uid, gid, 0o664,
		map[string]string{
			"HTTP_PORT": strconv.Itoa(httpPort),
		},
	)
	if err := os.MkdirAll(etcSystemdSystem, 0o755); err != nil {
		log.Fatalf("cant create %s: %v", etcSystemdSystem, err)
	}
	InstallConfigFile(
		path.Join(systemdDir, "yajudge.slice"),
		path.Join(etcSystemdSystem, "yajudge.slice"),
		0, 0, 0o644,
		map[string]string{
			"YAJUDGE_HOME":  yajudgeHome,
			"YAJUDGE_USER":  yajudgeUser.Name,
			"YAJUDGE_GROUP": yajudgeGroup.Name,
		},
	)
	CreatePlainText(
		"yajudge",
		path.Join(confDir, "database-password.txt"),
		uid, gid, 0o660,
	)
	CreatePlainText(
		GeneratePrivateToken(),
		path.Join(confDir, "private-token.txt"),
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
	parentDir := path.Clean(path.Join(executableDir, "../.."))
	return parentDir, nil
}

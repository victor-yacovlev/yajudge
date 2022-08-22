package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/user"
	"path"
	"strconv"
)

func main() {
	skipUidCheck := flag.Bool("force", false, "skip UID check")
	yajudgeUserName := flag.String("U", "yajudge", "user name to run service")
	yajudgeGroupName := flag.String("G", "yajudge", "group name to run service")
	yajudgeSliceName := flag.String("S", "yajudge", "systemd slice name to place service")
	flag.Parse()
	if os.Geteuid() != 0 && !*skipUidCheck {
		log.Fatalf("Requires root privileges to ensure correct file permissions")
		os.Exit(1)
	}
	yajudgeRoot, err := resolveYajudgeRootDir()
	if err != nil {
		log.Fatalf("cant resolve yajudge installation root directory: %v", err)
	}
	yajudgeUser, err := user.Lookup(*yajudgeUserName)
	if err != nil {
		log.Fatalf("cant find user %s: %v", *yajudgeUserName, err)
	}
	yajudgeGroup, err := user.LookupGroup(*yajudgeGroupName)
	if err != nil {
		log.Fatalf("cant find group %s: %v", *yajudgeGroupName, err)
	}
	uid, _ := strconv.Atoi(yajudgeUser.Uid)
	gid, _ := strconv.Atoi(yajudgeGroup.Gid)
	logDir := path.Join(yajudgeRoot, "log")
	pidDir := path.Join(yajudgeRoot, "pid")
	cacheDir := path.Join(yajudgeRoot, "cache")
	workDir := path.Join(yajudgeRoot, "work")
	sockDir := path.Join(yajudgeRoot, "sock")
	sliceDir := path.Join("/sys/fs/cgroup", *yajudgeSliceName+".slice")
	mustEnsureDirectoryWritable(logDir, uid, gid)
	mustEnsureDirectoryWritable(pidDir, uid, gid)
	mustEnsureDirectoryWritable(cacheDir, uid, gid)
	mustEnsureDirectoryWritable(workDir, uid, gid)
	mustEnsureDirectoryWritable(sockDir, uid, gid)
	mustEnsureDirectoryWritable(sliceDir, uid, gid)
}

func mustEnsureDirectoryWritable(dirPath string, uid, gid int) {
	if err := os.MkdirAll(dirPath, 0o770); err != nil {
		log.Fatalf("cant create directory %s: %v", dirPath, err)
	}
	if err := chownRecursive(dirPath, uid, gid); err != nil {
		log.Fatalf("cant chown: %v", err)
	}
}

func chownRecursive(dirPath string, uid, gid int) error {
	if err := os.Chown(dirPath, uid, gid); err != nil {
		return fmt.Errorf("while processing %s: %v", dirPath, err)
	}
	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return fmt.Errorf("while processing %s: %v", dirPath, err)
	}
	for _, entry := range entries {
		fullPath := path.Join(dirPath, entry.Name())
		if entry.IsDir() {
			if err := chownRecursive(fullPath, uid, gid); err != nil {
				return err
			}
		} else {
			if err := os.Chown(fullPath, uid, gid); err != nil {
				return fmt.Errorf("while processing %s: %v", fullPath, err)
			}
		}
	}
	return nil
}

func resolveYajudgeRootDir() (string, error) {
	scriptExecutable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("cant resolve yajudge directory: %v", err)
	}
	if stat, _ := os.Lstat(scriptExecutable); stat.Mode()&os.ModeSymlink != 0 {
		scriptExecutable, _ = os.Readlink(scriptExecutable)
	}
	executableDir := path.Dir(scriptExecutable)
	if !path.IsAbs(executableDir) {
		cwd, _ := os.Getwd()
		executableDir = path.Clean(path.Join(cwd, executableDir))
	}
	dirBaseName := path.Base(executableDir)
	var parentDir string
	if dirBaseName == "bin" {
		// packaged into bundle
		parentDir = path.Clean(path.Join(executableDir, ".."))
	} else {
		// development
		parentDir = path.Clean(path.Join(executableDir, "../.."))
	}
	return parentDir, nil
}

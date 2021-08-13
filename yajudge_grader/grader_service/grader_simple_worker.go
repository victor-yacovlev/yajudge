package grader_service

// This is not secure worker implementation!
// You must run in as much isolated as possible!

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"
	. "yajudge_server/core_service"
)

type Worker struct {
	Runtimes []string
}

func (worker Worker) GetName() string {
	hostname, _ := os.Hostname()
	arch := runtime.GOARCH
	os := runtime.GOOS
	return fmt.Sprintf("%s (%s, %s)", hostname, os, arch)
}

func (worker Worker) GetArch() Arch {
	switch runtime.GOARCH {
	case "386", "i386", "i586", "i686":
		return Arch_ARCH_X86
	case "x86_64", "amd64":
		return Arch_ARCH_X86_64
	case "arm":
		return Arch_ARCH_ARMV7
	case "aarch64":
		return Arch_ARCH_AARCH64
	default:
		panic(fmt.Errorf("unknown runtime.GOARCH=%s", runtime.GOARCH))
	}
}

func (worker Worker) GetOs() OS {
	switch strings.ToLower(runtime.GOOS) {
	case "darwin", "macos":
		return OS_OS_DARWIN
	case "linux":
		return OS_OS_LINUX
	case "windows":
		return OS_OS_WINDOWS
	default:
		panic(fmt.Errorf("unknown runtime.GOOS=%s", runtime.GOOS))
	}
}

func (worker Worker) GetSupportedRuntimes() []string {
	return worker.Runtimes
}

func NewWorker(runtimes []string) *Worker {
	worker := &Worker{
		Runtimes: runtimes,
	}
	return worker
}

func (worker *Worker) CheckStyle(rootDir string, solution *File) (ok bool, failedFileName string, err error) {

	args := []string{"-i", "-style=file", solution.Name}
	checker := exec.Command("clang-format", args...)
	checker.Dir = rootDir
	err = checker.Run()
	if err != nil {
		return false, "", fmt.Errorf("cant start clang-format: %v", err)
	}
	styledContent, err := os.ReadFile(rootDir + string(os.PathSeparator) + solution.Name)
	if err != nil {
		return false, "", fmt.Errorf("cant open styled file %s: %v", solution.Name, err)
	}
	if bytes.Equal(styledContent, solution.Data) {
		return true, "", nil
	} else {
		return false, solution.Name, nil
	}
}

func (worker *Worker) BuildTarget(rootDir string, target *GradingTarget) (ok bool, report string, err error) {
	report = ""
	for _, buildStage := range target.BuildCommands {
		args := strings.Split(buildStage, " ")
		firstArg := args[0]
		restArgs := args[1:]
		command := exec.Command(firstArg, restArgs...)
		command.Dir = rootDir
		reportData, err := command.CombinedOutput()
		exitCode := 0
		if err != nil {
			switch err.(type) {
			case *exec.ExitError:
				exitError := err.(*exec.ExitError)
				exitCode = exitError.ExitCode()
			default:
				return false, "", fmt.Errorf("cant start '%s': %v", buildStage, err)
			}
		}
		command.Wait()
		report += string(reportData)
		if exitCode != 0 {
			return false, report, nil
		}
	}
	return true, report, nil
}

func (worker *Worker) RunTarget(rootDir string, rt *GradingRuntime, target *GradingTarget,
	testDir string,
	testCase *TestCase,
	limits *GradingLimits) (ok bool, status int, stdout, stderr []byte, err error) {
	err = os.MkdirAll(testDir, 0700)
	if err != nil {
		err = fmt.Errorf("can't create directory for test: %v", err)
		return
	}
	testCaseProgram := ".." + string(os.PathSeparator) + target.TargetFileName
	testCaseArgs := strings.Split(testCase.CommandLineArguments, " ")
	var programToLaunch string
	var programArgs []string
	if rt.Name == "" || strings.HasPrefix(rt.Name, "default") {
		programToLaunch = testCaseProgram
		programArgs = testCaseArgs
	} else {
		programToLaunch = rt.Name
		switch rt.Name {
		case "valgrind":
			programArgs = worker.valgrindOpts()
		case "qemu-arm":
			programArgs = worker.qemuOpts(limits)
		}
		programArgs = append(programArgs, testCaseProgram)
		programArgs = append(programArgs, testCaseArgs...)
	}
	if rt.Name == "wine" || runtime.GOOS == "windows" {
		for i := 0; i < len(programArgs); i++ {
			programArgs[i] = strings.ReplaceAll(programArgs[i], "/", string(os.PathSeparator))
		}
	}
	if testCase.InputExtraFiles != nil {
		for _, inputFile := range testCase.InputExtraFiles.Files {
			inputFileName := testDir + string(os.PathSeparator) + inputFile.Name
			err = os.WriteFile(inputFileName, inputFile.Data, 0600)
			if err != nil {
				err = fmt.Errorf("cant create input test file %s: %v", inputFile, err)
				return
			}
		}
	}
	if limits == nil {
		limits = &GradingLimits{
			RealTimeLimitSec: 20,
			ProcCountLimit:   10,
			StackSizeLimitMb: 8,
			VmSizeLimitMb:    1024,
			FdCountLimit:     20,
		}
	}
	return worker.RunProcessWithLimits(testDir, programToLaunch, programArgs,
		testCase.StdinData.Data, limits)
}

func (worker *Worker) RunProcessWithLimits(rootDir, programToLaunch string,
	programArgs []string, stdinData []byte, limits *GradingLimits) (ok bool, status int, stdout, stderr []byte, err error) {

	// WARNING: Not secure implementation!!!
	realTimeLimit := time.Duration(limits.RealTimeLimitSec) * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), realTimeLimit)
	defer cancel()
	command := exec.CommandContext(ctx, programToLaunch, programArgs...)
	inBuffer := bytes.NewBuffer(stdinData)
	command.Stdin = inBuffer
	var stdoutBuffer bytes.Buffer
	var stderrBuffer bytes.Buffer
	command.Stdout = &stdoutBuffer
	command.Stderr = &stderrBuffer
	command.Dir = rootDir
	err = command.Run()
	if err != nil {
		switch err.(type) {
		case *exec.ExitError:
			// pass
		default:
			err = fmt.Errorf("cant start process: %v", err)
			return
		}
	}
	stdout = stdoutBuffer.Bytes()
	stderr = stderrBuffer.Bytes()
	ok = command.ProcessState.Exited()
	status = command.ProcessState.ExitCode()
	return
}

func (worker *Worker) valgrindOpts() []string {
	return []string{"--tool=memcheck", "--leak-check=full"}
}

func (worker *Worker) qemuOpts(limits *GradingLimits) []string {
	return []string{"-s", strconv.Itoa(int(limits.StackSizeLimitMb * 1024 * 1024))}
}

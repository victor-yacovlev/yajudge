package checkers

import (
	"bytes"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"yajudge_server/core_service"
)

//go:embed custom_checker_wrapper.py
var customCheckerWrapper string

type CheckerInterface interface {
	Match(observed []byte, standard []byte) (bool, error)
	SetTestDirPath(testDirPath string)
}

func StandardCheckerByName(name string) CheckerInterface {
	var result CheckerInterface
	switch name {
	case "int", "long":
		result = &CheckInt{}
	case "float", "double":
		result = &CheckFloat{}
	}
	return result
}

type PythonCheckerWrapper struct {
	PyModuleName	string
	RootDir			string
	TestDir			string
}

func (checker *PythonCheckerWrapper) SetTestDirPath(testDirPath string) {
	checker.TestDir = testDirPath
}

func (checker *PythonCheckerWrapper) Match(observed []byte, standard []byte) (bool, error) {
	observedSize := strconv.Itoa(len(observed))
	standardSize := strconv.Itoa(len(standard))
	pyWrapperPath := checker.RootDir + string(os.PathSeparator) + "custom_checker_wrapper.py"
	pyModulePath := checker.RootDir + string(os.PathSeparator) + checker.PyModuleName
	command := exec.Command("python3", pyWrapperPath, observedSize, standardSize, pyModulePath)
	inData := bytes.NewBuffer(append(observed, standard...))
	command.Stdin = inData
	command.Dir = checker.TestDir
	output, err := command.CombinedOutput()
	if err != nil {
		return false, err
	}
	status := command.ProcessState.ExitCode()
	switch status {
	case 0: return true, nil
	case 1: return false, nil
	default: return false, fmt.Errorf("checker error: %s", string(output))
	}
}

func BuildCustomCheckerFromPythonSource(rootDir string, file *core_service.File) (res CheckerInterface, err error) {
	err = os.WriteFile(rootDir + string(os.PathSeparator) + file.Name, file.Data, 0600)
	if err != nil {
		return
	}
	err = os.WriteFile(rootDir + string(os.PathSeparator) + "custom_checker_wrapper.py", []byte(customCheckerWrapper), 0600)
	if err != nil {
		return
	}
	res = &PythonCheckerWrapper{
		PyModuleName: file.Name,
		RootDir:      rootDir,
	}
	return
}

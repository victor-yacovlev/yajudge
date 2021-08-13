package checkers

import (
	"bytes"
	"fmt"
	"math"
)

type CheckInt struct {
}

func (checker *CheckInt) Match(observed []byte, standard []byte) (bool, error) {
	o := bytes.NewReader(observed)
	s := bytes.NewReader(standard)
	var o_val, s_val int64
	for s_n, s_err := fmt.Fscanf(s, "%d", &s_val); s_err != nil && s_n > 0; {
		o_n, o_err := fmt.Fscanf(o, "%d", &o_val)
		if o_err == nil || o_n == 0 {
			return false, nil
		}
		if s_val != o_val {
			return false, nil
		}
	}
	return true, nil
}

func (checker *CheckInt) SetTestDirPath(testDirPath string) {}

type CheckFloat struct {
	Epsilon float64
}

func (checker *CheckFloat) Match(observed []byte, standard []byte) (bool, error) {
	o := bytes.NewReader(observed)
	s := bytes.NewReader(standard)
	var o_val, s_val float64
	for s_n, s_err := fmt.Fscanf(s, "%g", &s_val); s_err != nil && s_n > 0; {
		o_n, o_err := fmt.Fscanf(o, "%g", &o_val)
		if o_err == nil || o_n == 0 {
			return false, nil
		}
		if math.Abs(s_val-o_val) > checker.Epsilon {
			return false, nil
		}
	}
	return true, nil
}

func (checker *CheckFloat) SetTestDirPath(testDirPath string) {}

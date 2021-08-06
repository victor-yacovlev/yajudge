package checkers

type CheckerInterface interface {
	Match(observed []byte, standard []byte) bool
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

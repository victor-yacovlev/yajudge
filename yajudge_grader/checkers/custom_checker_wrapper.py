import os
from typing import List
import sys
import importlib.util


def main(args: List[str]) -> int:
    print(os.getcwd())
    observed_size = int(args[1])
    standard_size = int(args[2])
    observed = sys.stdin.buffer.read(observed_size)
    standard = sys.stdin.buffer.read(standard_size)
    assert isinstance(observed, bytes)
    assert isinstance(standard, bytes)
    module_file_name = args[3]
    spec = importlib.util.spec_from_file_location("checker", module_file_name)
    if spec is None:
        sys.stdout.write('Cant create spec from python file')
        return 2
    module = importlib.util.module_from_spec(spec)
    if module is None:
        sys.stdout.write('Cant load python module')
        return 3
    try:
        spec.loader.exec_module(module)
    except BaseException as e:
        sys.stdout.write(str(e))
        return 4
    try:
        match = module.match(observed, standard)
    except BaseException as e:
        sys.stdout.write(str(e))
        return 5
    if match:
        return 0
    else:
        return 1


if __name__ == '__main__':
    main_args = sys.argv
    ret = main(main_args)
    sys.exit(ret)

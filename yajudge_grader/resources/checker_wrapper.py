import sys
import importlib.util
import os
from typing import List


def import_module(module_file_name: str):
    spec = importlib.util.spec_from_file_location('checker', module_file_name)
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    return checker


def read_file_as_bytes(file_name: str) -> bytes:
    result = b''
    with open(file_name, 'rb') as f:
        result = f.read()
    return result


def read_args_file(file_name: str) -> List[str]:
    result = []
    src = ''
    with open(file_name, 'r') as f:
        src = f.read().strip()
    if file_name.endswith('.inf'):
        parts = src.split('=')
        if len(parts) < 2:
            return []
        key = parts[0].strip()
        value = parts[1].strip()
        if key == 'params':
            result = value.split(' ')
    else:
        result = src.split(' ')
    return result


def main():
    checker_file_name = sys.argv[1]
    work_dir_path = sys.argv[2]
    args_file_name = sys.argv[3]
    stdin_file_name = sys.argv[4]
    stdout_file_name = sys.argv[5]
    reference_file_name = sys.argv[6]
    module = import_module(checker_file_name)
    stdout = read_file_as_bytes(stdout_file_name)
    reference = b''
    if os.path.exists(reference_file_name):
        reference = read_file_as_bytes(reference_file_name)
    stdin = b''
    if os.path.exists(stdin_file_name):
        stdin = read_file_as_bytes(stdin_file_name)
    args = []
    if os.path.exists(args_file_name):
        args = read_args_file(args_file_name)
    os.chdir(work_dir_path)
    result = module.match(args, stdin, stdout, reference)
    if result:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()

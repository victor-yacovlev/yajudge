import sys
import importlib.util
import os

def import_module(module_file_name: str):
    spec = importlib.util.spec_from_file_location('checker', module_file_name)
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    return checker

def read_file_as_bytes(file_name: str) -> bytes:
    result = bytes()
    with open(file_name, 'rb') as f:
        result = f.read()
    return result

def main():
    checker_file_name = sys.argv[1]
    work_dir_path = sys.argv[2]
    observed_file_name = sys.argv[3]
    reference_file_name = sys.argv[4]
    module = import_module(checker_file_name)
    observed = read_file_as_bytes(observed_file_name)
    reference = read_file_as_bytes(reference_file_name)
    os.chdir(work_dir_path)
    result = module.match(observed, reference)
    if result:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
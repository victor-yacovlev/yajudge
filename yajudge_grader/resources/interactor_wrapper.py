import sys
import importlib.util
import os


def import_module(module_file_name: str):
    spec = importlib.util.spec_from_file_location('interactor', module_file_name)
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    return checker


def read_file_as_bytes(file_name: str) -> bytes:
    result = b''
    with open(file_name, 'rb') as f:
        result = f.read()
    return result


def main():
    interactor_file_name = sys.argv[1]
    work_dir_path = sys.argv[2]
    input_data_file_name = sys.argv[3]
    module = import_module(interactor_file_name)
    input_data = b''
    if os.path.exists(input_data_file_name):
        input_data = read_file_as_bytes(input_data_file_name)
    os.chdir(work_dir_path)
    input_stream = sys.stdin.buffer
    output_stream = sys.stdout.buffer
    module.interact(input_data, output_stream, input_stream)


if __name__ == '__main__':
    main()

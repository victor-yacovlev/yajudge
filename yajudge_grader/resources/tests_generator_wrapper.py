import sys
import importlib.util
import os


def import_module(module_file_name: str):
    spec = importlib.util.spec_from_file_location('tests_generator', module_file_name)
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    return generator


def main():
    generator_file_name = sys.argv[1]
    work_dir_path = sys.argv[2]
    module = import_module(generator_file_name)
    os.chdir(work_dir_path)

    tests_count = module.get_tests_count()
    assert isinstance(tests_count, int)

    for test_number in range(1, 1 + tests_count):
        test_base_name = str(test_number)
        if test_number < 10:
            test_base_name = '0' + test_base_name
        if test_number < 100:
            test_base_name = '0' + test_base_name

        if 'generate_directory_content' in module.__dict__:
            subdir_name = work_dir_path + '/' + test_base_name + '.dir'
            if not os.path.exists(subdir_name):
                os.mkdir(subdir_name)
            os.chdir(subdir_name)
            print(f'Generating test {test_number} directory content in {os.getcwd()}', end='')
            module.generate_directory_content(test_number)
            print(' OK')
            os.chdir(work_dir_path)

        if 'generate_answer' in module.__dict__:
            ans_name = work_dir_path + '/' + test_base_name + '.ans'
            print(f'Generating test {test_number} answer file {test_base_name}.ans', end='')
            with open(ans_name, 'wb') as f:
                f.write(module.generate_answer(test_number))
            print(' OK')

        if 'generate_input' in module.__dict__:
            dat_name = work_dir_path + '/' + test_base_name + '.dat'
            print(f'Generating test {test_number} input file {test_base_name}.dat', end='')
            with open(dat_name, 'wb') as f:
                f.write(module.generate_input(test_number))
            print(' OK')

        if 'generate_arguments' in module.__dict__:
            inf_name = work_dir_path + '/' + test_base_name + '.inf'
            print(f'Generating test {test_number} params file {test_base_name}.dat', end='')
            arguments = module.generate_arguments(test_number)
            if arguments:
                line = 'params = ' + ' '.join(arguments)
                with open(inf_name, 'w') as f:
                    f.write(line + '\n')
            print(' OK')

    with open('.tests_count', 'w') as f:
        f.write(f'{tests_count}\n')


if __name__ == '__main__':
    main()

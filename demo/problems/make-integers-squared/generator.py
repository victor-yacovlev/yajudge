import random
from typing import List
from random import randint

random.seed()
_RandomsCount = 1000
_RandomInput = [randint(-10000, 10000) for _ in range(0, _RandomsCount)]


def get_tests_count() -> int:
    return 1


def generate_directory_content(test_number: int):
    _ = test_number
    pass


def generate_answer(test_number: int) -> bytes:
    _ = test_number
    return (' '.join([str(x*x) for x in _RandomInput])).encode('utf-8')


def generate_input(test_number: int) -> bytes:
    _ = test_number
    return (' '.join([str(x) for x in _RandomInput])).encode('utf-8')


def generate_arguments(test_number: int) -> List[str]:
    _ = test_number
    return []

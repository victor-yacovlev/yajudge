from typing import List


def match(args: List[str], stdin: bytes, reference: bytes) -> bool:
    _ = args
    in_str = stdin.decode('utf-8')
    ref_str = reference.decode('utf-8')
    in_values = in_str.split()
    ref_values = ref_str.split()
    if len(in_values) != len(ref_values):
        print(f'Values count mismatch: expected {len(ref_values)}, got {len(in_values)}')
        return False
    for a, b in zip(ref_values, in_values):
        if a != b:
            print(f'Value mismatch: expected {a}, got {b}')
            return False
    return True

from typing import List


def match(args: List[str], stdin: bytes, stdout: bytes, reference: bytes) -> bool:
    _ = args, stdin
    ref_str = reference.decode('utf-8')
    out_str = stdout.decode('utf-8')
    ref_values = ref_str.split()
    out_values = out_str.split()
    if len(ref_values) != len(out_values):
        print(f'Values count mismatch: expected {len(ref_values)}, got {len(out_values)}')
        return False
    for a, b in zip(ref_values, out_values):
        if a != b:
            print(f'Value mismatch: expected {a}, got {b}')
            return False
    return True

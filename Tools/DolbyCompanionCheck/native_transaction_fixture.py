"""Explicit generated Swift integration adapter; never packaged or called by the app."""
import json
from pathlib import Path
import sys

import check
import writer


def main():
    if len(sys.argv) != 7:
        raise check.Refused('Generated adapter arguments')
    phase, source, stage, retention, executable, reader = sys.argv[1:]
    if phase == 'produce':
        result = writer.produce(Path(source), Path(stage), Path(executable), retention)
    elif phase == 'verify':
        result = check.validate(Path(source), Path(stage), Path(reader))
    else:
        raise check.Refused('Generated adapter phase')
    output = json.dumps(result).encode()
    if len(output) > 16384:
        raise check.Refused('Generated adapter output bound')
    sys.stdout.buffer.write(output + b'\n')


if __name__ == '__main__':
    try:
        main()
    except (check.Refused, OSError):
        print('Generated companion phase refused.', file=sys.stderr)
        sys.exit(1)

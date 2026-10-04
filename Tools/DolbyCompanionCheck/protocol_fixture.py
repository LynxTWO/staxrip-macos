"""Generated protocol capture for Swift parser tests, never packaged by the app.

This transport is not a native controller or its cancellation qualification.
It emits only the actual writer's bounded stdout after the child settles.
"""
import subprocess
import sys


def main():
    if len(sys.argv) != 10:
        raise ValueError('Arguments')
    executable, mode, source, stage, operation, *ids = sys.argv[1:]
    if mode not in ('metadata', 'full') or len(operation) != 32:
        raise ValueError('Control')
    child = subprocess.Popen([executable, mode, source, stage, operation, *ids],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        output, _ = child.communicate(('start ' + operation + '\n').encode(), timeout=120)
        if child.returncode != 0 or len(output) > 32768:
            raise ValueError('Result')
        sys.stdout.buffer.write(output)
    finally:
        if child.poll() is None:
            child.kill()
        child.wait()
        child.stdin.close()
        child.stdout.close()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.TimeoutExpired):
        print('Generated protocol capture refused.', file=sys.stderr)
        sys.exit(1)

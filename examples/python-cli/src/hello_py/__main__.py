"""hello-py: a tiny CLI that shows how shipcrate fits into a real Python program.
The only shipcrate-specific lines are marked "shipcrate"."""
import sys

from . import __version__
from . import update_check  # shipcrate: copied from updater/update_check.py


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args[0] if args else None
    if cmd in ("--version", "-V"):
        print(f"hello-py {__version__}")
    elif cmd == "upgrade":  # shipcrate: `hello-py upgrade [--rollback]`
        print(update_check.upgrade(__version__, rollback="--rollback" in args))
    else:
        print(f"👋 Hello, {cmd or 'world'}! (hello-py {__version__})")
        update_check.notify(__version__)  # shipcrate: daily notice / announcement, interactive use only
    return 0


if __name__ == "__main__":
    sys.exit(main())

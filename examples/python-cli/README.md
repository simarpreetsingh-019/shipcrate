# hello-py: a Python CLI with shipcrate

```sh
cd src && python3 -m hello_py Ada         # 👋 Hello, Ada!  (+ the update notice)
python3 -m hello_py upgrade               # verified upgrade of the single-file build
python3 -I tests/test_hello.py            # its tests (shipcrate's own run in the gate too)
```

shipcrate-specific code: [`src/hello_py/__main__.py`](src/hello_py/__main__.py) (lines marked `shipcrate`), plus
`src/hello_py/update_check.py`, a copy of `updater/update_check.py`.

**Releases.** `release.conf` builds a single-file zipapp (`build/hello-py`) that runs anywhere with Python 3, so one
build covers macOS, Linux and Windows (`TARGETS='any'`). People who install with pip or pipx are told to upgrade
with pipx/pip instead: the updater detects that.

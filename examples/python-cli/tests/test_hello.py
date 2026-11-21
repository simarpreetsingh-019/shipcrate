import io, sys, unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from hello_py.__main__ import main  # noqa: E402


class Hello(unittest.TestCase):
    def test_greets(self):
        out = io.StringIO()
        with redirect_stdout(out):
            main(["Ada"])
        self.assertIn("Hello, Ada!", out.getvalue())


if __name__ == "__main__":
    unittest.main()

import site
import sys
from pathlib import Path

SP_DIR = Path(site.getsitepackages()[0])
STUBS = ["distutils", "setuptools"]


def main() -> int:
    for stub in STUBS:
        stub_path = SP_DIR / f"{stub}-stubs/__init__.pyi"
        assert stub_path.exists(), f"{stub_path} does not exist"
    return 0


if __name__ == "__main__":
    sys.exit(main())

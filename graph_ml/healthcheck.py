from __future__ import annotations

import json
import platform
import sys


def environment_info() -> dict[str, str]:
    return {
        "status": "ok",
        "python_version": platform.python_version(),
        "implementation": platform.python_implementation(),
        "executable": sys.executable,
    }


def main() -> None:
    print(json.dumps(environment_info(), sort_keys=True))


if __name__ == "__main__":
    main()

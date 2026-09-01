#!/usr/bin/env python3
"""Build the Codex code-mode host with the upstream verified V8 artifacts."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: build-code-mode-host.py /path/to/codex")

    source_root = Path(sys.argv[1]).resolve()
    os.environ["CODEX_REPO_ROOT"] = str(source_root)
    sys.path.insert(0, str(source_root / "scripts"))

    from codex_package.targets import TARGET_SPECS
    from codex_package.v8 import resolve_codex_v8_cargo_env

    spec = TARGET_SPECS["aarch64-apple-darwin"]
    environment = {**os.environ, **resolve_codex_v8_cargo_env(spec)}
    subprocess.run(
        [
            "cargo",
            "build",
            "--target",
            spec.target,
            "--profile",
            "release",
            "--bin",
            "codex-code-mode-host",
        ],
        cwd=source_root / "codex-rs",
        env=environment,
        check=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Pre-convert knowledge-base sources so the Lambda never needs PDF tooling.

Converts data/me/linkedin.pdf to data/me/linkedin.md with pymupdf4llm. Run it
whenever the PDF changes (deploy.py runs it automatically):

    uv run build_knowledge.py

pymupdf4llm and its dependencies (pymupdf, onnxruntime, numpy) are ~190 MB and
load a layout model at import time, which is far too heavy for the 512 MB Lambda.
Keeping them out of requirements.txt makes the package small and the cold start fast.
"""

from __future__ import annotations

import sys
from pathlib import Path

PDF_PATH = Path(__file__).parent / "data" / "me" / "linkedin.pdf"
MD_PATH = Path(__file__).parent / "data" / "me" / "linkedin.md"


def build() -> Path:
    import pymupdf4llm  # imported lazily: only needed at build time

    markdown = pymupdf4llm.to_markdown(str(PDF_PATH))
    MD_PATH.write_text(markdown, encoding="utf-8")
    return MD_PATH


def main() -> int:
    if not PDF_PATH.exists():
        print(f"No PDF at {PDF_PATH}; leaving {MD_PATH.name} as is.")
        return 0
    path = build()
    print(f"Wrote {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

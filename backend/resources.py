import json
import os
from datetime import date

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


def _read(*parts: str) -> str:
    with open(os.path.join(DATA_DIR, *parts), "r", encoding="utf-8") as f:
        return f.read()


def _load_linkedin() -> str:
    """Prefer the pre-converted markdown (see build_knowledge.py).

    Falling back to converting the PDF keeps local development working before the
    markdown exists, but the Lambda package deliberately ships without pymupdf4llm.
    """
    md_path = os.path.join(DATA_DIR, "me", "linkedin.md")
    if os.path.exists(md_path):
        return _read("me", "linkedin.md")
    pdf_path = os.path.join(DATA_DIR, "me", "linkedin.pdf")
    if os.path.exists(pdf_path):
        try:
            import pymupdf4llm

            return pymupdf4llm.to_markdown(pdf_path)
        except ImportError:
            return "LinkedIn profile not available (run `uv run build_knowledge.py`)"
    return "LinkedIn profile not available"


linkedin = _load_linkedin()
summary = _read("me", "summary.md")
style = _read("style.txt")

# profile.json is the single source of truth for facts about Patrick.
# The frontend consumes a copy of the same file (frontend/content/profile.json).
profile = json.loads(_read("profile.json"))


def years_of_experience(today: date | None = None) -> int:
    """Whole years since profile['career_start'] (YYYY-MM)."""
    today = today or date.today()
    year, month = (int(part) for part in profile["career_start"].split("-"))
    years = today.year - year
    if (today.month) < month:
        years -= 1
    return max(years, 0)


# Backwards-compatible alias; prefer `profile`.
facts = profile

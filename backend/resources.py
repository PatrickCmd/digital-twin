import json
from datetime import date

import pymupdf4llm

# Read LinkedIn PDF
try:
    linkedin = pymupdf4llm.to_markdown("./data/me/linkedin.pdf")

except FileNotFoundError:
    linkedin = "LinkedIn profile not available"

# Read other data files
with open("./data/me/summary.md", "r", encoding="utf-8") as f:
    summary = f.read()

with open("./data/style.txt", "r", encoding="utf-8") as f:
    style = f.read()

# profile.json is the single source of truth for facts about Patrick.
# The frontend consumes a copy of the same file (frontend/content/profile.json).
with open("./data/profile.json", "r", encoding="utf-8") as f:
    profile = json.load(f)


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

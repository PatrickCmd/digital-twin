import pymupdf4llm
import json

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

with open("./data/facts.json", "r", encoding="utf-8") as f:
    facts = json.load(f)
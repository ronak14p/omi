from functools import lru_cache
from pathlib import Path
from typing import Dict


MAX_DOC_CHARS_PER_FILE = 24_000


@lru_cache(maxsize=1)
def get_omi_docs_content() -> Dict[str, str]:
    """
    Return a lightweight, cached set of product docs for in-chat product Q&A.
    """
    repo_root = Path(__file__).resolve().parents[3]
    candidates = [
        ('README', repo_root / 'README.md'),
        ('MVP Interaction Flow', repo_root / 'Mar4' / 'MVP_INTERACTION_FLOW.MD'),
        ('Initial Transformation', repo_root / 'Mar4' / 'INITIAL_TRANSFORMATION.MD'),
    ]

    docs: Dict[str, str] = {}
    for section, path in candidates:
        if not path.exists():
            continue
        content = path.read_text(encoding='utf-8', errors='ignore').strip()
        if not content:
            continue
        docs[section] = content[:MAX_DOC_CHARS_PER_FILE]

    if not docs:
        docs['Documentation'] = 'Product documentation is temporarily unavailable.'

    return docs

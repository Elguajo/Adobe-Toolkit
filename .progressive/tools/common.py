from pathlib import Path
import re

PHASE_RE = re.compile(r"^- \[(?P<marker>[ >x])\].*?`(?P<path>(?:docs|\.progressive)/phases/[^`]+\.md)`", re.M)

PREFIX_MAP = {
    'docs/project/': '.progressive/project/',
    'docs/phases/': '.progressive/phases/',
    'docs/decisions/': '.progressive/decisions/',
    'docs/system/': '.progressive/system/',
    'integrations/': '.progressive/integrations/',
    'templates/': '.progressive/templates/',
    'prompts/': '.progressive/prompts/',
    'tools/': '.progressive/tools/',
}

def read(p: Path):
    return p.read_text(encoding='utf-8') if p.is_file() else ''

def chars(p: Path):
    return len(read(p))

def is_runtime(root: Path) -> bool:
    return (root / '.progressive' / 'VERSION').is_file()

def safe_join(root: Path, rel: str) -> Path:
    """Resolve rel under root, rejecting absolute paths, traversal, and symlink escapes."""
    if not rel or Path(rel).is_absolute():
        raise ValueError(f'path must be relative and non-empty: {rel!r}')
    root_r = root.resolve()
    target = (root_r / rel).resolve()
    try:
        target.relative_to(root_r)
    except ValueError:
        raise ValueError(f'path escapes repository root: {rel!r}')
    return target

def resolve_path(root: Path, rel: str) -> Path:
    if is_runtime(root):
        for old, new in PREFIX_MAP.items():
            if rel.startswith(old):
                rel = new + rel[len(old):]
                break
    return safe_join(root, rel)

def project_file(root: Path, name: str) -> Path:
    return resolve_path(root, f'docs/project/{name}')

def template_file(root: Path, name: str) -> Path:
    return resolve_path(root, f'templates/{name}')

def integration_file(root: Path, name: str) -> Path:
    return resolve_path(root, f'integrations/{name}')

def current_phase(root: Path):
    road = read(project_file(root, 'ROADMAP.md'))
    for m in PHASE_RE.finditer(road):
        if m.group('marker') == '>':
            try:
                p = safe_join(root, m.group('path'))
            except ValueError:
                return None
            return p if p.is_file() else None
    return None

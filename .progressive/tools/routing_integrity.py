#!/usr/bin/env python3
from pathlib import Path
import argparse, json, re

ALLOWED_ACTIVATION = {'automatic', 'explicit', 'both'}


def _frontmatter(text: str):
    m = re.match(r'^---\n(.*?)\n---(?:\n|$)', text, re.S)
    if not m:
        return {}
    data = {}
    for line in m.group(1).splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        data[key.strip()] = value.strip()
    return data


def _list_field(meta, key, skill, errors):
    raw = meta.get(key)
    if raw is None:
        return []
    try:
        value = json.loads(raw)
    except Exception:
        errors.append(f'{skill} {key} must be a JSON string array')
        return []
    if not isinstance(value, list) or any(not isinstance(x, str) or not x.strip() for x in value):
        errors.append(f'{skill} {key} must be a JSON string array')
        return []
    return value


def _router_file(root: Path):
    source_router = root / 'profiles/personal/AGENTS.md'
    return source_router if source_router.is_file() else root / 'AGENTS.md'


def _workflow_section(text: str):
    m = re.search(r'^## Workflow routing\s*$\n(.*?)(?=^##\s|\Z)', text, re.M | re.S)
    return m.group(1) if m else ''


def validate(root: Path):
    root = root.resolve()
    errors = []
    skills = {}

    for path in sorted((root / '.agents/skills').glob('*/SKILL.md')):
        name = path.parent.name
        meta = _frontmatter(path.read_text(encoding='utf-8'))
        declared = meta.get('name', '')
        activation = meta.get('activation', '')
        if declared != name:
            errors.append(f'Skill frontmatter name mismatch: {name}')
        if activation not in ALLOWED_ACTIVATION:
            errors.append(f'Skill activation invalid for routing: {name}={activation or "<missing>"}')
        skills[name] = {
            'activation': activation,
            'requires': _list_field(meta, 'requires', name, errors),
            'may_delegate': _list_field(meta, 'may_delegate', name, errors),
        }

    router = _router_file(root)
    if not router.is_file():
        errors.append('routing file missing')
        return errors, {'skills': len(skills), 'routed': 0, 'requires': 0, 'delegates': 0}

    section = _workflow_section(router.read_text(encoding='utf-8'))
    if not section:
        errors.append('Workflow routing section missing')
        routed = set()
    else:
        routed = set(re.findall(r'→\s*`([a-z0-9-]+)`', section))

    for name in sorted(routed - set(skills)):
        errors.append('router references missing Skill: ' + name)

    for name, data in sorted(skills.items()):
        activation = data['activation']
        if activation in {'automatic', 'both'} and name not in routed:
            errors.append('automatic Skill not routed: ' + name)
        if activation == 'explicit' and name in routed:
            errors.append('explicit Skill routed automatically: ' + name)

        for rel in data['requires']:
            if not (root / rel).is_file():
                errors.append(f'{name} requires missing path: {rel}')

        for target in data['may_delegate']:
            if target == name:
                errors.append(f'{name} may_delegate cannot target itself')
                continue
            if target not in skills:
                errors.append(f'{name} may_delegate target missing: {target}')
                continue
            if skills[target]['activation'] == 'explicit':
                errors.append(f'{name} may_delegate targets explicit-only Skill: {target}')

    summary = {
        'skills': len(skills),
        'routed': len(routed),
        'requires': sum(len(x['requires']) for x in skills.values()),
        'delegates': sum(len(x['may_delegate']) for x in skills.values()),
    }
    return errors, summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='.')
    args = ap.parse_args()
    errors, summary = validate(Path(args.root))
    for error in errors:
        print('ERROR:', error)
    if errors:
        print(f'ROUTING INTEGRITY: FAIL ({len(errors)} errors)')
        return 1
    print(
        'ROUTING INTEGRITY: PASS '
        f"({summary['routed']}/{summary['skills']} auto-routed or explicit-exempt Skills, "
        f"{summary['requires']} required path edges, {summary['delegates']} delegation edges)"
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

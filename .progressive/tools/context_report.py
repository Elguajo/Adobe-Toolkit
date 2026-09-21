#!/usr/bin/env python3
from pathlib import Path
import argparse, json, re
from common import chars, current_phase, is_runtime, project_file, resolve_path, template_file
from context_compile import completion_bridge

FRONTMATTER_RE = re.compile(r'\A---\n(.*?\n)---\n', re.S)


def skill_metadata_chars(path: Path) -> int:
    text = path.read_text(encoding='utf-8') if path.is_file() else ''
    m = FRONTMATTER_RE.match(text)
    return len(m.group(0)) if m else 0


def collect(root: Path, profile: str, agent: str = 'codex') -> dict:
    global_p = root / ('global/CLAUDE.md' if agent == 'claude' else 'global/AGENTS.codex.md')
    personal_p = root / 'profiles/personal/AGENTS.md'
    standalone_p = root / 'profiles/standalone/AGENTS.md'
    phase = current_phase(root) or template_file(root, 'PHASE.template.md')
    project = [
        project_file(root, 'PROJECT_BRIEF.md'),
        project_file(root, 'ARCHITECTURE.md'),
        project_file(root, 'ROADMAP.md'),
        phase,
    ]
    skills = sorted((root / '.agents/skills').glob('*/SKILL.md'))
    skill_metadata_total = sum(skill_metadata_chars(p) for p in skills)
    skill_full_body_total = sum(chars(p) for p in skills)
    if is_runtime(root):
        # Project Runtime is self-contained by default; root AGENTS.md is the actual always-loaded repo layer.
        global_chars = 0
        repo_chars = chars(root / 'AGENTS.md')
        always = repo_chars
        profile = (root / '.progressive/PROFILE').read_text(encoding='utf-8').strip() if (root / '.progressive/PROFILE').is_file() else profile
    elif profile == 'personal':
        always = chars(global_p) + chars(personal_p)
        global_chars = chars(global_p)
        repo_chars = chars(personal_p)
    else:
        always = chars(standalone_p)
        global_chars = 0
        repo_chars = chars(standalone_p)
    project_chars = sum(chars(p) for p in project)
    if current_phase(root):
        _, record = completion_bridge(root, current_phase(root))
        project_chars += len(record)
    archived = root / 'docs/migration/ORIGINAL_CUSTOM_INSTRUCTIONS.txt'
    old_chars = chars(archived)
    behavior_contract = root / 'docs/migration/BEHAVIOR_CONTRACT.json'
    behavior_scenarios = root / 'docs/evals/static/BEHAVIOR_SCENARIOS.json'
    behavior_rule_count = 0
    behavior_scenario_count = 0
    framework_rule_count = 0
    framework_scenario_count = 0
    preferred_tool_count = 0
    try:
        behavior_rule_count = json.loads(behavior_contract.read_text(encoding='utf-8')).get('rule_count', 0)
        behavior_scenario_count = json.loads(behavior_scenarios.read_text(encoding='utf-8')).get('scenario_count', 0)
    except Exception:
        pass
    try:
        framework_rule_count = json.loads((root / 'docs/contracts/FRAMEWORK_CONTRACT.json').read_text(encoding='utf-8')).get('rule_count', 0)
        framework_scenario_count = len(json.loads((root / 'docs/evals/static/FRAMEWORK_SCENARIOS.json').read_text(encoding='utf-8')).get('scenarios', []))
        preferred_tool_count = len(json.loads((root / 'integrations/TOOL_REGISTRY.json').read_text(encoding='utf-8')).get('tools', {}))
    except Exception:
        pass
    result = {
        'profile': profile,
        'agent': agent,
        'global_chars': global_chars,
        'repo_chars': repo_chars,
        'always_loaded_chars': always,
        'always_loaded_token_estimate_rough': round(always / 4),
        'project_default_chars': project_chars,
        'project_default_token_estimate_rough': round(project_chars / 4),
        'skill_count': len(skills),
        'largest_skill_chars': max([chars(p) for p in skills] or [0]),
        'skill_metadata_chars_loaded': skill_metadata_total,
        'skill_full_body_chars_not_loaded': skill_full_body_total - skill_metadata_total,
        'behavior_rule_count': behavior_rule_count,
        'behavior_scenario_count': behavior_scenario_count,
        'framework_rule_count': framework_rule_count,
        'framework_scenario_count': framework_scenario_count,
        'preferred_tool_count': preferred_tool_count,
    }
    if old_chars:
        result['archived_old_custom_instructions_chars'] = old_chars
        result['reduction_vs_old_custom_alone_pct'] = round((1 - always / old_chars) * 100, 1)
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='.')
    ap.add_argument('--profile', choices=['personal','standalone'], default='personal')
    ap.add_argument('--agent', choices=['codex','claude'], default='codex')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--baseline-chars', type=int)
    args = ap.parse_args()
    data = collect(Path(args.root).resolve(), args.profile, args.agent)
    if args.baseline_chars:
        data['baseline_chars'] = args.baseline_chars
        data['always_loaded_reduction_vs_baseline_pct'] = round((1 - data['always_loaded_chars'] / args.baseline_chars) * 100, 1)
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        for key, value in data.items():
            print(f'{key}: {value}')
        print('NOTE: token estimates use chars/4 only as rough English-heavy intuition, not exact model billing.')


if __name__ == '__main__':
    main()

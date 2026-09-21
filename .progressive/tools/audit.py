#!/usr/bin/env python3
from pathlib import Path
import argparse, json, re
from common import chars, current_phase, project_file, read, resolve_path, template_file
from context_compile import completion_bridge, completion_record
from routing_integrity import validate as validate_routing_integrity
from tool_adapter_protocol import validate as validate_tool_adapters

EXPECTED_SKILLS = {'architecture-decision','code-review','documentation-governance','project-bootstrap','existing-project-adoption','tooling-bootstrap','project-doctor','security-sensitive-change','session-handoff','systematic-debugging','workflow-audit','implementation-execution'}
ALLOWED_SKILL_ACTIVATION = {'automatic','explicit','both'}
EXPECTED_TOOLS = {'semble','serena','rtk','superpowers','gstack','context7','github_spec_kit'}
REQUIRED = [
    'AGENTS.md','CLAUDE.md','.progressive/VERSION','.progressive/PROFILE','.progressive/AGENT_TARGET','.progressive/ADOPTION_STATE',
    '.progressive/project/PROJECT_BRIEF.md','.progressive/project/ARCHITECTURE.md','.progressive/project/ROADMAP.md','.progressive/project/NEXT_SESSION.md','.progressive/project/CONTEXT_MANIFEST.json','.progressive/project/TOOLING_STATUS.json',
    '.progressive/system/CONTEXT_PROTOCOL.md','.progressive/system/HANDOFF_PROTOCOL.md','.progressive/system/LAYER_OWNERSHIP.md','.progressive/system/PLANNING_DEPTH.md','.progressive/system/QUALITY_PROTOCOL.md','.progressive/system/TOOL_ROUTING.md','.progressive/system/UBIQUITOUS_LANGUAGE.md',
    '.progressive/integrations/TOOL_ADAPTER_PROTOCOL.md','.progressive/integrations/TOOL_REGISTRY.json','.progressive/integrations/PROFILES.md',
    '.progressive/templates/PHASE.template.md','.progressive/templates/PHASE_COMPLETION.template.md','.progressive/tools/common.py','.progressive/tools/context_compile.py','.progressive/tools/routing_integrity.py','.progressive/tools/audit.py','.progressive/tools/tool_adapter_protocol.py','.progressive/tools/tooling_status.py','.progressive/tools/tooling_bootstrap.py',
]
# Real products may legitimately own root directories named docs/, tools/, templates/,
# integrations/, profiles/, or prompts/. Detect legacy Framework Source leakage by
# framework-specific sentinel paths instead of reserving generic project directory names.
LEGACY_FRAMEWORK_MARKERS = [
    'docs/project/PROJECT_BRIEF.md',
    'docs/system/CONTEXT_PROTOCOL.md',
    'global/AGENTS.codex.md',
    'profiles/standalone/AGENTS.md',
    'prompts/START_NEW_PROJECT.md',
    'templates/PHASE.template.md',
    'integrations/TOOL_REGISTRY.json',
    'tools/context_compile.py',
]

def fail_if(c, errors, msg):
    if c: errors.append(msg)


def project_skill_path(root, name):
    return root / '.agents' / 'skills' / name / 'SKILL.md'


def global_skill_roots():
    home = Path.home()
    return (home / '.codex' / 'skills', home / '.agents' / 'skills')


def verify_skill_resolution(root, errors, warns):
    """Validate project-owned routed Skills without treating global-only Skills as conflicts."""
    for name in sorted(EXPECTED_SKILLS):
        primary = project_skill_path(root, name)
        global_matches = [base / name / 'SKILL.md' for base in global_skill_roots()]
        found = [path for path in global_matches if path.is_file()]
        if not primary.is_file():
            message = f'Expected project Skill is missing: PRIMARY: {primary}'
            if found:
                message += '; ALSO FOUND: ' + ', '.join(str(path) for path in found)
            errors.append(message)
            continue
        if found:
            warns.append(
                f'Skill collision for {name}: PRIMARY: {primary}; ALSO FOUND: '
                + ', '.join(str(path) for path in found)
                + '; project-local wins'
            )


def verify_skills(root, errors):
    a = {p.parent.name:p for p in (root/'.agents/skills').glob('*/SKILL.md')}
    c = {p.parent.name:p for p in (root/'.claude/skills').glob('*/SKILL.md')}
    if set(a) != EXPECTED_SKILLS: errors.append('Skill set mismatch')
    if set(a) != set(c): errors.append('Codex/Claude Skill sets differ')
    for name in set(a) & set(c):
        if a[name].read_bytes() != c[name].read_bytes(): errors.append('Skill mirror drift: '+name)
        text = read(a[name])
        ma = re.search(r'^activation:\s*(.+)$', text, re.M)
        if not ma or not ma.group(1).strip():
            errors.append('Skill activation missing: '+name)
        elif ma.group(1).strip() not in ALLOWED_SKILL_ACTIVATION:
            errors.append('Skill activation invalid: '+name+'='+ma.group(1).strip())

def verify_tooling(root, errors):
    try:
        reg = json.loads(read(resolve_path(root,'integrations/TOOL_REGISTRY.json')))
        status = json.loads(read(project_file(root,'TOOLING_STATUS.json')))
    except Exception as exc:
        errors.append('invalid tooling JSON: '+str(exc)); return
    if set(reg.get('tools',{})) != EXPECTED_TOOLS: errors.append('Tool Registry set mismatch')
    for key in EXPECTED_TOOLS:
        if key not in status.get('tools',{}): errors.append('tooling status missing tool: '+key)

def verify_ubiquitous_language(root, warns):
    brief = read(project_file(root,'PROJECT_BRIEF.md'))
    match = re.search(r'^## Ubiquitous Language\s*$\n(.*?)(?=^## |\Z)', brief, re.M | re.S)
    if not match:
        return
    section = match.group(1)
    entries = [line for line in section.splitlines() if re.match(r'^ {0,3}-\s+\S', line)]
    if len(entries) > 12:
        warns.append(f'Project Brief Ubiquitous Language exceeds 12-term guidance: {len(entries)} terms')
    if len(section) > 1800:
        warns.append(f'Project Brief Ubiquitous Language is large for default context: {len(section)} chars')
    terms = []
    malformed = []
    for line in entries:
        body = re.sub(r'^ {0,3}-\s+', '', line).strip()
        parts = re.split(r'\s+[—-]\s+', body, maxsplit=1)
        if len(parts) != 2 or not all(part.strip() for part in parts):
            malformed.append(body)
            continue
        term = parts[0].strip()
        for marker in ('**', '__', '`', '*', '_'):
            if term.startswith(marker) and term.endswith(marker) and len(term) > 2 * len(marker):
                term = term[len(marker):-len(marker)].strip()
                break
        term = re.sub(r'\s+', ' ', term).casefold()
        if term:
            terms.append(term)
    if malformed:
        sample = ', '.join(value[:80] for value in malformed[:3])
        suffix = f' (+{len(malformed) - 3} more)' if len(malformed) > 3 else ''
        warns.append('Project Brief Ubiquitous Language has malformed entries: '+sample+suffix)
    duplicates = sorted({term for term in terms if terms.count(term) > 1})
    if duplicates:
        warns.append('Project Brief Ubiquitous Language repeats canonical terms: '+', '.join(duplicates))


def verify_next_session(root, errors):
    """Lint declared non-runnable handoffs without judging task completion semantically."""
    text = read(project_file(root, 'NEXT_SESSION.md'))
    match = re.search(r'^## Current working state\s*$\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not match:
        return
    lines = [line.strip() for line in match.group(1).splitlines() if line.strip()]
    if not lines or lines[0].startswith('<'):
        return
    state = lines[0]
    allowed = {'RUNNABLE / GREEN', 'KNOWN BROKEN / RECOVERABLE', 'BLOCKED'}
    if state not in allowed:
        errors.append('NEXT_SESSION has invalid current working state: '+state)
        return
    if state == 'RUNNABLE / GREEN':
        return
    section = match.group(1)
    for field in ('Why', 'First recovery action'):
        if not re.search(rf'^- {re.escape(field)}:\s*\S', section, re.M):
            errors.append(f'NEXT_SESSION {state} requires non-empty "- {field}:"')

def verify_project_state(root, errors, warns):
    road = read(project_file(root,'ROADMAP.md'))
    markers = re.findall(r'^- \[([ >x])\].*?`((?:docs|\.progressive)/phases/[^`]+\.md)`', road, re.M)
    if markers:
        active = [p for marker,p in markers if marker == '>']
        if len(active) > 1: errors.append('Roadmap has more than one active phase')
        if not active and not all(marker == 'x' for marker,_ in markers): errors.append('Initialized Roadmap must have exactly one active phase unless all phases are complete')
        for marker,rel in markers:
            p = root/rel
            # Completed and active phases are execution evidence and must exist. Planned
            # future phases may remain Roadmap-only until they become active.
            if marker in {'x','>'} and not p.is_file():
                errors.append('Roadmap phase file missing: '+rel)
                continue
            if marker == 'x' and p.is_file() and not completion_record(p):
                warns.append('completed phase lacks Completion Record: '+rel)
    verify_ubiquitous_language(root, warns)
    verify_next_session(root, errors)
    phase = current_phase(root) or template_file(root,'PHASE.template.md')
    project_chars = sum(chars(project_file(root,n)) for n in ['PROJECT_BRIEF.md','ARCHITECTURE.md','ROADMAP.md']) + chars(phase)
    if current_phase(root):
        _, record = completion_bridge(root,current_phase(root)); project_chars += len(record)
    if project_chars > 22000: warns.append(f'project default context exceeds 22000-char soft budget: {project_chars}')

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',default='.'); a=ap.parse_args(); root=Path(a.root).resolve(); errors=[]; warns=[]
    for rel in REQUIRED: fail_if(not (root/rel).is_file(), errors, 'missing required runtime file: '+rel)
    for rel in LEGACY_FRAMEWORK_MARKERS:
        fail_if((root/rel).exists(), errors, 'legacy framework surface leaked into project root: '+rel)
    fail_if('@AGENTS.md' not in read(root/'CLAUDE.md'), errors, 'CLAUDE.md must import @AGENTS.md')
    fail_if('.progressive/' not in read(root/'AGENTS.md'), errors, 'AGENTS.md must route into hidden .progressive runtime')
    if (root/'.progressive/PROFILE').is_file(): fail_if(read(root/'.progressive/PROFILE').strip() not in {'standalone','personal'},errors,'invalid runtime PROFILE')
    if (root/'.progressive/ADOPTION_STATE').is_file(): fail_if(read(root/'.progressive/ADOPTION_STATE').strip() == 'pending',errors,'existing-project adoption is pending; reconcile conflicts and finalize adoption')
    if (root/'.progressive/AGENT_TARGET').is_file(): fail_if(read(root/'.progressive/AGENT_TARGET').strip() not in {'codex','claude','both'},errors,'invalid AGENT_TARGET')
    verify_skill_resolution(root,errors,warns); verify_skills(root,errors); verify_tooling(root,errors); verify_project_state(root,errors,warns)
    routing_errors,_ = validate_routing_integrity(root); errors += routing_errors
    adapter_errors,adapter_warns = validate_tool_adapters(root); errors += adapter_errors; warns += adapter_warns
    for x in errors: print('ERROR:',x)
    for x in warns: print('WARN:',x)
    if errors:
        print(f'RUNTIME AUDIT: FAIL ({len(errors)} errors, {len(warns)} warnings)'); return 1
    print(f'RUNTIME AUDIT: PASS (0 errors, {len(warns)} warnings)'); return 0
if __name__=='__main__': raise SystemExit(main())

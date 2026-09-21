#!/usr/bin/env python3
from pathlib import Path
import argparse, json, re, sys
from common import PHASE_RE, current_phase, project_file, read, resolve_path, safe_join

CORE=['docs/project/PROJECT_BRIEF.md','docs/project/ARCHITECTURE.md','docs/project/ROADMAP.md','docs/project/NEXT_SESSION.md']
PLACEHOLDER_PATTERNS=[r'^Status:\s*UNINITIALIZED\s*$',r'^<.*>$',r'^\.\.\.$']
MAX_REQUIRED_FILES=16
MAX_TOTAL_EXTRA_CHARS=16000


def compact(text):
    lines=[]
    for line in text.splitlines():
        if any(re.match(p,line.strip()) for p in PLACEHOLDER_PATTERNS):
            if line.strip().startswith('Status:'): lines.append(line.rstrip())
            continue
        if not line.strip() and (not lines or not lines[-1].strip()): continue
        lines.append(line.rstrip())
    return '\n'.join(lines).strip()


def roadmap_entries(root):
    road=read(project_file(root,'ROADMAP.md'))
    entries=[]
    for m in PHASE_RE.finditer(road):
        try:
            p=safe_join(root,m.group('path'))
        except ValueError:
            continue
        entries.append((m.group('marker'),m.group('path'),p))
    return entries


def previous_completed_phase(root, phase):
    if not phase: return None
    target=phase.resolve()
    entries=roadmap_entries(root)
    for i,(_,_,p) in enumerate(entries):
        if p.resolve()!=target: continue
        if i==0: return None
        marker,_,prev=entries[i-1]
        return prev if marker=='x' and prev.is_file() else None
    return None


def completion_record(path):
    if not path or not path.is_file(): return ''
    text=read(path)
    m=re.search(r'^## Completion Record\s*$\n?(.*?)(?=^##\s|\Z)',text,re.M|re.S)
    if not m: return ''
    return compact(m.group(1))


def completion_bridge(root, phase=None):
    phase=phase or current_phase(root)
    prev=previous_completed_phase(root,phase)
    if not prev: return None,''
    return prev,completion_record(prev)


def manifest_for_phase(root, phase):
    p=project_file(root,'CONTEXT_MANIFEST.json')
    if not p.is_file(): return {'required':[],'skills':[],'notes':[]}
    try: data=json.loads(p.read_text(encoding='utf-8'))
    except Exception: return {'required':[],'skills':[],'notes':['WARNING: invalid CONTEXT_MANIFEST.json']}
    result={'required':[],'skills':[],'notes':[]}
    for src in [data.get('default',{}), data.get('phases',{}).get(phase.relative_to(root).as_posix(),{}) if phase else {}]:
        for k in result:
            result[k].extend(x for x in src.get(k,[]) if x not in result[k])
    return result


def build(root,max_extra_chars=4000):
    root=root.resolve()
    phase=current_phase(root)
    chunks=['# Compiled Current Context','Generated deterministically; canonical files remain source of truth.']
    for rel in CORE:
        text=compact(read(resolve_path(root,rel)))
        if text: chunks.append(f'## {rel}\n{text}')
    if phase:
        text=compact(read(phase)); chunks.append(f'## {phase.relative_to(root).as_posix()}\n{text}')
        prev,record=completion_bridge(root,phase)
        if prev and record:
            chunks.append(f'## Previous phase completion bridge — {prev.relative_to(root).as_posix()}\n{record}')
    hints=manifest_for_phase(root,phase)
    if hints['skills']: chunks.append('## Skill hints\n'+'\n'.join('- '+x for x in hints['skills']))
    if hints['notes']: chunks.append('## Context notes\n'+'\n'.join('- '+x for x in hints['notes']))
    if hints['required']:
        required=hints['required']
        overflow=len(required)-MAX_REQUIRED_FILES
        parts=[]
        total=0
        for rel in required[:MAX_REQUIRED_FILES]:
            try:
                p=resolve_path(root,rel)
            except ValueError as e:
                parts.append(f'### {rel}\nREJECTED — {e}'); continue
            if not p.is_file(): parts.append(f'### {rel}\nMISSING — verify manifest/repository state.'); continue
            text=read(p)
            if len(text)>max_extra_chars:
                parts.append(f'### {rel}\nPOINTER ONLY — {len(text)} chars exceeds compact inline limit; read targeted sections if needed.'); continue
            if total+len(text)>MAX_TOTAL_EXTRA_CHARS:
                parts.append(f'### {rel}\nPOINTER ONLY — manifest total-context budget ({MAX_TOTAL_EXTRA_CHARS} chars) reached; read targeted sections if needed.'); continue
            total+=len(text); parts.append(f'### {rel}\n{text.strip()}')
        if overflow>0:
            parts.append(f'### (budget)\n{overflow} additional manifest-required file(s) omitted — exceeds max_required_files ({MAX_REQUIRED_FILES}).')
        chunks.append('## Manifest-required context\n'+'\n\n'.join(parts))
    return '\n\n'.join(chunks).strip()+'\n'


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',default='.'); ap.add_argument('--output'); ap.add_argument('--max-extra-chars',type=int,default=4000); a=ap.parse_args(); root=Path(a.root).resolve()
    text=build(root,a.max_extra_chars)
    if a.output:
        out=Path(a.output); out=out if out.is_absolute() else root/out; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8'); print(out)
    else:
        # Context can contain any Unicode from project documentation.  Force UTF-8
        # instead of inheriting a legacy Windows code page such as CP1251.
        try: sys.stdout.reconfigure(encoding='utf-8')
        except (AttributeError, ValueError): pass
        print(text,end='')
if __name__=='__main__': main()

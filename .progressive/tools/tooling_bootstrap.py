#!/usr/bin/env python3
from pathlib import Path
import argparse, json
from common import integration_file, project_file

def choose(tier,risk,advanced):
    if advanced: return 'advanced_spec'
    if tier=='S' and risk=='Low': return 'minimal'
    return 'recommended'

def main():
    ap=argparse.ArgumentParser(description='Plan preferred tooling; does not install or modify user/global configuration.')
    ap.add_argument('--root',default='.'); ap.add_argument('--tier',choices=['S','M','L'],required=True); ap.add_argument('--risk',choices=['Low','Medium','High'],required=True); ap.add_argument('--advanced-spec',action='store_true')
    a=ap.parse_args(); root=Path(a.root).resolve(); reg=json.loads(integration_file(root,'TOOL_REGISTRY.json').read_text(encoding='utf-8')); status=json.loads(project_file(root,'TOOLING_STATUS.json').read_text(encoding='utf-8'))
    profile=choose(a.tier,a.risk,a.advanced_spec); print('selected_profile:',profile)
    wanted=[]
    for key,t in reg['tools'].items():
        if profile=='minimal': continue
        if profile=='recommended' and 'recommended' not in t.get('profiles',[]): continue
        if profile=='advanced_spec' and not ({'recommended','advanced_spec'} & set(t.get('profiles',[]))): continue
        wanted.append(key)
    for key in wanted:
        s=status['tools'].get(key,{}).get('status','not_checked'); brand=reg['tools'][key]['brand']; print(f'{key}: {brand} status={s} official={reg["tools"][key]["official"]}')
    print('NOTE: This command only plans. Use tooling-bootstrap Skill for current official docs, approval, installation/configuration, verification, and persisted status.')
if __name__=='__main__': main()

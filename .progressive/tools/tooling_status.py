#!/usr/bin/env python3
from pathlib import Path
import argparse, datetime as dt, json, shlex, shutil, subprocess
from common import integration_file, project_file

ALLOWED={'not_checked','not_detected','available','configured','degraded','declined','not_applicable'}

def load(root):
    reg=json.loads(integration_file(root,'TOOL_REGISTRY.json').read_text(encoding='utf-8'))
    p=project_file(root,'TOOLING_STATUS.json')
    status=json.loads(p.read_text(encoding='utf-8')) if p.is_file() else {'schema':1,'profile':'not_selected','last_bootstrap':None,'tools':{}}
    for k in reg['tools']:
        status.setdefault('tools',{}).setdefault(k,{'status':'not_checked','checked_at':None,'version':None,'evidence':None,'notes':None})
    return reg,status

def now(): return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()

def write(root,status):
    p=project_file(root,'TOOLING_STATUS.json'); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(status,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    lines=['# Tooling Status','',f"Profile: {status.get('profile','not_selected')}",f"Last bootstrap: {status.get('last_bootstrap') or 'never'}",'','| Tool | Status | Version | Evidence |','|---|---|---|---|']
    for k,v in status['tools'].items(): lines.append(f"| {k} | {v.get('status')} | {v.get('version') or ''} | {(v.get('evidence') or '').replace('|','/')} |")
    project_file(root,'TOOLING_STATUS.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

def probe(root,reg,status):
    for key,tool in reg['tools'].items():
        cmds=tool.get('probe_commands') or []
        if not cmds: continue
        exe=shlex.split(cmds[0])[0]
        entry=status['tools'][key]; entry['checked_at']=now()
        if not shutil.which(exe):
            entry['status']='not_detected'; entry['evidence']=f'{exe} not found on local PATH; agent/MCP integration may still exist'; continue
        try:
            r=subprocess.run(shlex.split(cmds[0]),capture_output=True,text=True,timeout=4)
            out=(r.stdout or r.stderr).strip().splitlines()
            entry['status']='available' if r.returncode==0 else 'degraded'
            entry['version']=out[0][:160] if out else None
            entry['evidence']=f'local probe: {cmds[0]} exit={r.returncode}'
        except Exception as exc:
            entry['status']='degraded'; entry['evidence']='probe error: '+str(exc)

def report(reg,status):
    print('profile:',status.get('profile','not_selected'))
    for k,tool in reg['tools'].items():
        v=status['tools'][k]
        print(f"{tool['brand']}: {v.get('status')} | {tool['capability']} | version={v.get('version') or '-'}")

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',default='.')
    ap.add_argument('--report',action='store_true'); ap.add_argument('--probe',action='store_true')
    ap.add_argument('--set',dest='tool'); ap.add_argument('--status',choices=sorted(ALLOWED)); ap.add_argument('--version'); ap.add_argument('--evidence'); ap.add_argument('--notes')
    ap.add_argument('--profile',choices=['not_selected','minimal','recommended','advanced_spec'])
    a=ap.parse_args(); root=Path(a.root).resolve(); reg,status=load(root); changed=False
    if a.probe: probe(root,reg,status); changed=True
    if a.profile: status['profile']=a.profile; status['last_bootstrap']=now(); changed=True
    if a.tool:
        if a.tool not in reg['tools']: raise SystemExit('unknown tool: '+a.tool)
        if not a.status: raise SystemExit('--set requires --status')
        e=status['tools'][a.tool]; e.update(status=a.status,checked_at=now(),version=a.version,evidence=a.evidence,notes=a.notes); changed=True
    if changed: write(root,status)
    if a.report or not changed: report(reg,status)
if __name__=='__main__': main()

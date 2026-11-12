#!/usr/bin/env python3
"""Read-only system detail/status and explicitly requested safe UDisks eject.

Only allowlisted summaries cross into diagnostics: never raw auth output, environment,
user paths, device names, network addresses, logs or tokens.
"""
import ipaddress
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys


def command_status(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=12)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return -1, ''


def read_text(args):
    return command_status(args)[1]


def read_json(args):
    try: return json.loads(read_text(args))
    except (ValueError, TypeError): return []


def network(interface):
    if not interface or '/' in interface or '\0' in interface:
        return dict(ipv4=[], ipv6=[], gateways=[], dns=[])
    addresses = read_json(['ip', '-j', 'address', 'show', 'dev', interface])
    result = dict(ipv4=[], ipv6=[], gateways=[], dns=[])
    for device in addresses:
        if device.get('ifname') != interface: continue
        for address in device.get('addr_info', []):
            key = {'inet':'ipv4', 'inet6':'ipv6'}.get(address.get('family'))
            if key: result[key].append(f"{address['local']}/{address['prefixlen']}")
    for family in ('-4', '-6'):
        for route in read_json(['ip', '-j', family, 'route', 'show', 'default', 'dev', interface]):
            gateway = route.get('gateway')
            if gateway and gateway not in result['gateways']: result['gateways'].append(gateway)
    for value in read_text(['nmcli', '-g', 'IP4.DNS,IP6.DNS', 'device', 'show', interface]).splitlines():
        try:
            value = str(ipaddress.ip_address(value.strip().replace('\\:', ':')))
            if value not in result['dns']: result['dns'].append(value)
        except ValueError: pass
    return result


DEPENDENCIES = [
    ('qs','Shell','Required'), ('python3','Python helpers','Required'),
    ('wl-copy','Clipboard','Required'), ('grim','Screenshots','Optional'),
    ('slurp','Region selection','Optional'), ('gpu-screen-recorder','Recording','Optional'),
    ('ffmpeg','Recording trim','Optional'), ('pw-record','Microphone check','Optional'),
    ('pw-play','Audio playback','Optional'), ('nmcli','Ethernet details','Optional'),
    ('udisksctl','Drive eject','Optional'),
    ('hyprsunset','Night light','Optional'), ('ddcutil','Display brightness','Optional'),
    ('pdftoppm','PDF preview','Optional'), ('claude','Claude Code','Optional'),
    ('codex','Codex','Optional')]


def shell_errors(pid):
    code, output = command_status(['qs','log','--pid',str(pid),'--tail','200','--no-color'])
    count=sum(1 for line in output.splitlines()[-200:] if re.match(r'^\s*(?:ERROR|FATAL)(?:\s|:)',line))
    return dict(id='shell-errors',title='Recent shell errors',detail='Last 200 log lines · raw content excluded',status=(str(count)+' recent errors') if code==0 else 'Log unavailable')


def health(auth=False, pid=None):
    rows = [dict(id=tool, title=title, detail=kind, status='Installed' if shutil.which(tool) else 'Missing') for tool,title,kind in DEPENDENCIES]
    if pid is not None: rows.insert(0,shell_errors(pid))
    rows.insert(0,dict(id='shell',title='Shell',detail='Settings service active',status='Running'))
    for filename,title in [('lens.py','Lens helper'),('mic-check.py','Microphone helper')]:
        rows.append(dict(id=filename,title=title,detail='Installed helper source',status='Present' if Path(__file__).with_name(filename).is_file() else 'Missing'))
    # the helpers install.sh builds from rust/ into ~/.local/bin
    for binary,title in [('pistachio-auth','Polkit agent'),('pistachio-devices','Bluetooth agent and drive automount'),('pistachio-localsend','LocalSend helper')]:
        rows.append(dict(id=binary,title=title,detail='Built by install.sh',status='Present' if os.access(Path.home()/'.local/bin'/binary, os.X_OK) else 'Missing'))
    rows.append(dict(id='python-gi',title='Python D-Bus / GLib',detail='Required by the launcher and calendar helpers',status='Installed' if importlib.util.find_spec('gi') else 'Missing'))
    for tool, args in [('claude',['auth','status','--json']), ('codex',['login','status'])]:
        status = 'Not checked'
        if not shutil.which(tool): status = 'Not installed'
        elif auth:
            code, output = command_status([tool] + args)
            # Exit status is enough for Codex. Claude supplies a boolean, never publish its fields.
            if tool == 'claude' and code == 0:
                try: signed = json.loads(output).get('loggedIn', False) is True
                except (ValueError, AttributeError): signed = False
            else: signed = code == 0
            status = 'Signed in' if signed else 'Not signed in or unavailable'
        rows.append(dict(id=tool+'-auth',title=tool.title()+' authentication',detail='Local CLI status only',status=status))
    return rows


def bluetooth():
    result={}
    def address(item):
        props=item.get('properties',{})
        found=props.get('api.bluez5.address') or props.get('device.string')
        if not found:
            match=re.search(r'([0-9A-Fa-f]{2}(?:_[0-9A-Fa-f]{2}){5})',item.get('name',''))
            found=match.group(1).replace('_',':') if match else ''
        return found.upper() if re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}',found or '') else ''
    for card in read_json(['pactl','-f','json','list','cards']):
        addr=address(card)
        if addr: result[addr]={'profile':card.get('active_profile',''),'codec':'','rate':''}
    for node in read_json(['pactl','-f','json','list','sinks']) + read_json(['pactl','-f','json','list','sources']):
        addr=address(node)
        if not addr: continue
        detail=result.setdefault(addr,{'profile':'','codec':'','rate':''})
        props=node.get('properties',{})
        codec=props.get('api.bluez5.codec') or props.get('bluetooth.codec')
        rate=re.search(r'(\d+)Hz',node.get('sample_specification',''))
        if codec and not detail['codec']: detail['codec']=codec
        if rate and not detail['rate']: detail['rate']=rate.group(1)+' Hz'
    return result


def holders(mountpoint, proc=Path('/proc')):
    mount = os.path.realpath(mountpoint).rstrip('/') + '/'
    if mount == '/': return []
    found=[]
    for entry in sorted(proc.iterdir(), key=lambda p: int(p.name) if p.name.isdigit() else -1):
        if not entry.name.isdigit(): continue
        try:
            links = [entry/'cwd'] + list((entry/'fd').iterdir())
            busy=False
            for link in links:
                try: target=os.readlink(link)
                except OSError: continue
                if target.rstrip('/')+'/' == mount or target.startswith(mount): busy=True; break
            if busy:
                found.append(dict(pid=int(entry.name),name=(entry/'comm').read_text().strip()[:80]))
        except (OSError, PermissionError): continue
    return found


def device_mounted(device):
    """True/False only for a successful kernel lookup; errors remain unknown."""
    try:
        result=subprocess.run(['findmnt','--json','--kernel','--source',device,'--output','TARGET'],capture_output=True,text=True,timeout=5)
        if result.returncode==1 and not result.stdout.strip() and not result.stderr.strip(): return False
        if result.returncode!=0: return None
        filesystems=json.loads(result.stdout).get('filesystems')
        return bool(filesystems) if isinstance(filesystems,list) else None
    except (OSError,ValueError,AttributeError,subprocess.TimeoutExpired): return None


def eject(device, disk, name, mountpoint):
    # No shell strings, no force flags and never stop applications.
    code, _ = command_status(['udisksctl','unmount','--block-device',device,'--no-user-interaction'])
    if code != 0 and device_mounted(device) is not False:
        return dict(ok=False,name=name,holders=holders(mountpoint),message='Could not unmount. Close files on this drive, then retry. Some applications may be hidden by system permissions.')
    code, _ = command_status(['udisksctl','power-off','--block-device',disk,'--no-user-interaction'])
    return dict(ok=code==0,name=name,holders=[],message='Safe to remove.' if code==0 else 'Unmounted, but power-off failed. Retry after checking other volumes on this drive.')


if __name__ == '__main__':
    mode=sys.argv[1]
    if mode == 'network': result=network(sys.argv[2])
    elif mode == 'bluetooth': result=bluetooth()
    elif mode == 'health': result=health('--auth' in sys.argv[2:], int(sys.argv[sys.argv.index('--pid')+1]) if '--pid' in sys.argv else None)
    elif mode == 'eject': result=eject(*sys.argv[2:6])
    else: raise SystemExit('Unknown operation')
    print(json.dumps(result))

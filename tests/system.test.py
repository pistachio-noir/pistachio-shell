"""System helpers at external command/proc boundaries; never operate owner devices."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('system_tools', ROOT/'src/services/system-tools.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class SystemTests(unittest.TestCase):
    def test_network_limits_reading_to_selected_wired_interface(self):
        def run(args):
            if args[:3] == ['ip','-j','address']:
                return [{'ifname':'eth0','addr_info':[{'family':'inet','local':'192.0.2.4','prefixlen':24},{'family':'inet6','local':'2001:db8::4','prefixlen':64}]}]
            if args[:4] in (['ip','-j','-4','route'],['ip','-j','-6','route']): return [{'gateway':'192.0.2.1'}]
            return []
        with patch.object(m,'read_json',side_effect=run), patch.object(m,'read_text',return_value='192.0.2.53\n2001:db8::53'):
            result=m.network('eth0')
        self.assertEqual(result['ipv4'],['192.0.2.4/24'])
        self.assertEqual(result['ipv6'],['2001:db8::4/64'])
        self.assertIn('192.0.2.1',result['gateways'])
        self.assertEqual(result['dns'],['192.0.2.53','2001:db8::53'])
    def test_diagnostics_only_publish_allowlisted_status_not_auth_output(self):
        secret='secret-token /home/person/private 192.0.2.5 person@example.org'
        with patch.object(m.shutil,'which',return_value='/bin/tool'), patch.object(m,'command_status',side_effect=lambda args: (0, '{"loggedIn":true,"email":"' + secret + '"}') if args[0]=='claude' else (0,secret)):
            report=m.health(True)
        self.assertNotIn(secret,str(report))
        self.assertNotIn('192.0.2.5',str(report))
        self.assertEqual([r['status'] for r in report if r['id'] in ('claude-auth','codex-auth')],['Signed in','Signed in'])
    def test_drive_holders_resolve_fd_and_cwd_without_reading_files(self):
        with tempfile.TemporaryDirectory() as td:
            base=Path(td); mount=base/'mount'; mount.mkdir(); f=mount/'secret'; f.write_text('hidden')
            proc=base/'proc'; (proc/'44/fd').mkdir(parents=True); (proc/'44/comm').write_text('editor\n'); (proc/'44/fd/3').symlink_to(f)
            (proc/'45/fd').mkdir(parents=True); (proc/'45/comm').write_text('terminal\n'); (proc/'45/cwd').symlink_to(mount)
            self.assertEqual(m.holders(str(mount),proc),[{'pid':44,'name':'editor'},{'pid':45,'name':'terminal'}])
    def test_recent_errors_are_bounded_and_raw_lines_never_escape(self):
        private='email@example.org /home/person/private api-secret'
        with patch.object(m,'command_status',return_value=(0,'  ERROR scene: '+private+'\n  WARN: harmless\n ERROR: second\n')) as command:
            row=m.shell_errors(123)
        command.assert_called_once_with(['qs','log','--pid','123','--tail','200','--no-color'])
        self.assertEqual(row['status'],'2 recent errors')
        self.assertNotIn(private,str(row))
    def test_bluetooth_details_use_active_card_and_node_sample_spec(self):
        def read(args):
            if args[-1]=='cards': return [{'name':'bluez_card.AA_BB_CC_DD_EE_FF','properties':{},'active_profile':'a2dp-sink'}]
            if args[-1]=='sinks': return [{'properties':{'api.bluez5.address':'AA:BB:CC:DD:EE:FF','api.bluez5.codec':'aac'},'sample_specification':'float32le 2ch 48000Hz'}]
            return []
        with patch.object(m,'read_json',side_effect=read): result=m.bluetooth()
        self.assertEqual(result['AA:BB:CC:DD:EE:FF'],{'profile':'a2dp-sink','codec':'aac','rate':'48000 Hz'})
    def test_eject_never_powers_off_after_failed_unmount(self):
        calls=[]
        def status(args): calls.append(args); return (1,'busy')
        with patch.object(m,'command_status',side_effect=status), patch.object(m,'device_mounted',return_value=True,create=True), patch.object(m,'holders',return_value=[{'pid':44,'name':'editor'}]):
            result=m.eject('/dev/sdz1','/dev/sdz','USB','/mnt/USB')
        self.assertFalse(result['ok']); self.assertEqual(result['holders'][0]['pid'],44)
        self.assertEqual(len(calls),1)

    def test_mount_probe_distinguishes_absence_from_failure(self):
        from subprocess import CompletedProcess
        with patch.object(m.subprocess,'run',return_value=CompletedProcess([],1,'','')): self.assertIs(m.device_mounted('/dev/sdz1'),False)
        with patch.object(m.subprocess,'run',return_value=CompletedProcess([],1,'','lookup failed')): self.assertIsNone(m.device_mounted('/dev/sdz1'))
        with patch.object(m.subprocess,'run',return_value=CompletedProcess([],0,'{"filesystems":[{"target":"/mnt/USB"}]}','')): self.assertIs(m.device_mounted('/dev/sdz1'),True)

    def test_eject_retries_poweroff_after_successful_unmount(self):
        calls=[]
        responses=iter([(0,''),(1,'power-off failed'),(1,'not mounted'),(0,'')])
        def status(args): calls.append(args);return next(responses)
        with patch.object(m,'command_status',side_effect=status), patch.object(m,'device_mounted',return_value=False,create=True):
            first=m.eject('/dev/sdz1','/dev/sdz','USB','/mnt/USB')
            second=m.eject('/dev/sdz1','/dev/sdz','USB','/mnt/USB')
        self.assertFalse(first['ok']);self.assertTrue(second['ok'])
        self.assertEqual(sum(c[1]=='power-off' for c in calls),2)
    def test_mount_probe_errors_do_not_authorise_poweroff(self):
        with patch.object(m,'command_status',return_value=(1,'unmount failed')) as run,patch.object(m,'device_mounted',return_value=None,create=True),patch.object(m,'holders',return_value=[]):
            result=m.eject('/dev/sdz1','/dev/sdz','USB','/mnt/USB')
        self.assertFalse(result['ok']);self.assertEqual(run.call_count,1)

if __name__=='__main__': unittest.main()

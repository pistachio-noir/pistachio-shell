import importlib.util, pathlib, tempfile, unittest, time, threading, shutil
from urllib.parse import unquote, urlparse
from unittest.mock import patch, Mock
spec=importlib.util.spec_from_file_location('tools', pathlib.Path(__file__).parents[1]/'src/services/launcher-tools.py')
tools=importlib.util.module_from_spec(spec); spec.loader.exec_module(tools)
class ToolsTest(unittest.TestCase):
 def test_preview_is_bounded_and_binary_safe(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'żółć $() file.txt'; p.write_text('hello\n'*60000)
   result=tools.preview(str(p),d)
   self.assertEqual(result['kind'],'text'); self.assertTrue(result['truncated']); self.assertLessEqual(len(result['text']),262144)
   p.write_bytes(b'\x00binary'); self.assertEqual(tools.preview(str(p),d)['kind'],'metadata')
 def test_utf8_preview_truncates_on_a_character_boundary(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'unicode.txt';p.write_text('€'*90000)
   result=tools.preview(str(p),d)
   self.assertEqual(result['kind'],'text');self.assertTrue(result['truncated']);self.assertEqual(set(result['text']),{'€'})
 @unittest.skipUnless(shutil.which('pdftoppm'),'Poppler is optional')
 def test_real_pdf_first_page(self):
  with tempfile.TemporaryDirectory() as d:
   stream=b'BT /F1 12 Tf 20 50 Td (Pistachio) Tj ET'
   objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream',b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
   pdf=b'%PDF-1.4\n';offsets=[]
   for n,obj in enumerate(objects,1):
    offsets.append(len(pdf));pdf+=str(n).encode()+b' 0 obj\n'+obj+b'\nendobj\n'
   xref=len(pdf);pdf+=b'xref\n0 6\n0000000000 65535 f \n'+b''.join(f'{o:010} 00000 n \n'.encode() for o in offsets)
   pdf+=b'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+str(xref).encode()+b'\n%%EOF'
   p=pathlib.Path(d)/'first page.pdf';p.write_bytes(pdf)
   result=tools.preview(str(p),d);self.assertEqual(result['kind'],'image',result)
   image=pathlib.Path(unquote(urlparse(result['image']).path));self.assertTrue(image.read_bytes().startswith(b'\x89PNG'))
 def test_jobs_preserve_output_and_exit_code(self):
  with tempfile.TemporaryDirectory() as d:
   tools.run_job(pathlib.Path(d)/"one", "printf 'hello'; exit 7")
   state=tools.read_jobs(pathlib.Path(d))[0]
   self.assertEqual(state['code'],7); self.assertEqual(state['output'],'hello'); self.assertEqual(state['state'],'failed')
 def test_missing_preview_is_reported(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(OSError): tools.preview(d+'/missing',d)
 def test_cancel_reaps_running_command(self):
  with tempfile.TemporaryDirectory() as d:
   folder=pathlib.Path(d)/'cancelled'
   worker=threading.Thread(target=tools.run_job,args=(folder,"sleep 30")); worker.start()
   deadline=time.monotonic()+2
   while not (folder/'state.json').exists() and time.monotonic()<deadline: time.sleep(.01)
   (folder/'cancel').touch(); worker.join(4)
   self.assertFalse(worker.is_alive()); self.assertEqual(tools.read_jobs(pathlib.Path(d))[0]['state'],'cancelled')
 def test_job_output_error_reaps_child(self):
  original_read=tools.os.read
  def read(fd,size):
   if size==8192: raise OSError('fixture output failure')
   return original_read(fd,size)
  with tempfile.TemporaryDirectory() as d:
   with patch.object(tools.os,'read',side_effect=read),patch.object(tools.os,'killpg',wraps=tools.os.killpg) as kill:
    tools.run_job(pathlib.Path(d)/'io-error',"printf ready; sleep 30")
   self.assertTrue(kill.called);self.assertEqual(tools.read_jobs(pathlib.Path(d))[0]['state'],'failed')
 def test_output_tail_stays_bounded(self):
  with tempfile.TemporaryDirectory() as d:
   tools.run_job(pathlib.Path(d)/'long',"python3 -c 'print(chr(97)*300000)'")
   row=tools.read_jobs(pathlib.Path(d))[0]
   self.assertLessEqual(len(row['output']),65536)
   self.assertLessEqual((pathlib.Path(d)/'long/output').stat().st_size,131072)
 def test_open_with_remember_is_explicit(self):
  from gi.repository import Gio
  app=Mock(); app.get_id.return_value='fixture.desktop'
  with patch.object(tools,'handlers',return_value=('text/plain',[{'id':'fixture.desktop'}])), patch.object(Gio.AppInfo,'get_all_for_type',return_value=[app]):
   tools.open_with('/tmp/a name.txt','fixture.desktop',False)
   app.launch.assert_called_once(); app.set_as_default_for_type.assert_not_called()
   tools.open_with('/tmp/a name.txt','fixture.desktop',True)
   app.set_as_default_for_type.assert_called_once_with('text/plain')
   app.reset_mock();app.launch.return_value=False
   with self.assertRaises(ValueError): tools.open_with('/tmp/a name.txt','fixture.desktop',True)
   app.set_as_default_for_type.assert_not_called()
   with self.assertRaises(ValueError): tools.open_with('/tmp/a name.txt','unknown.desktop',True)
if __name__=='__main__': unittest.main()

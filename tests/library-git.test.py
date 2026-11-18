import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('library', Path(__file__).resolve().parents[1] / 'src/services/library.py')
library = importlib.util.module_from_spec(spec)
spec.loader.exec_module(library)

class GitStatusTest(unittest.TestCase):
    def test_clean_dirty_and_non_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            self.assertIsNone(library.git_status(str(path)))
            subprocess.run(['git', 'init', '-q', str(path)], check=True)
            status = library.git_status(str(path))
            self.assertTrue(status['branch'])
            self.assertFalse(status['dirty'])
            (path/'new.txt').write_text('hello')
            self.assertTrue(library.git_status(str(path))['dirty'])
            self.assertIsNone(library.git_status(str(path/'missing')))

if __name__ == '__main__': unittest.main()

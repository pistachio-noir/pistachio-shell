import importlib.util
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location('shared_theme', Path(__file__).resolve().parents[1] / 'src/services/shared-theme.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'pistachio/shared-theme'
    helper.publish(path, 'noir')
    assert path.read_text() == 'noir\n'
    helper.publish(path, 'pistachio')
    assert path.read_text() == 'pistachio\n'
    try:
        helper.publish(path, 'invalid')
        raise AssertionError('invalid scheme accepted')
    except ValueError:
        pass
    assert path.read_text() == 'pistachio\n'
print('shared theme publication: passed')

from unittest.mock import patch
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'pistachio/shared-theme'
    kitty = Path(folder) / 'kitty/pistachio-shared.conf'
    kitty.parent.mkdir()
    kitty.write_text('include pistachio-noir.conf\n')
    with patch.object(helper.subprocess, 'run') as run:
        run.return_value.returncode = 0
        helper.publish(path, 'noir')
        assert kitty.read_text() == 'include noir.conf\n'
        run.assert_called_once()
        helper.publish(path, 'noir')
        run.assert_called_once()
        helper.publish(path, 'pistachio')
        assert kitty.read_text() == 'include pistachio-noir.conf\n'
        assert run.call_count == 2
print('Kitty theme selection and reload: passed')

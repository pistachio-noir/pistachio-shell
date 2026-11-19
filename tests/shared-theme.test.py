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

# --- theming integration: the shell sets Kitty and Neovim up itself (19 November 2026) ---
import json, os, subprocess, sys
EXTRAS = Path(__file__).resolve().parents[1] / 'extras'
HELPER = Path(__file__).resolve().parents[1] / 'src/services/shared-theme.py'


def state(config, app):
    return next(a for a in helper.status(config) if a['id'] == app)


def backups(folder):
    return [p for p in folder.iterdir() if '.pistachio-bak-' in p.name]


with tempfile.TemporaryDirectory() as folder, patch.object(helper.shutil, 'which', return_value='/usr/bin/x'), \
        patch.object(helper.subprocess, 'run') as run:
    run.return_value.returncode = 0
    config = Path(folder)
    kitty = config / 'kitty'; kitty.mkdir()
    original = 'font_size 12\nbackground_opacity 0.9\n'
    (kitty / 'kitty.conf').write_text(original)
    assert state(config, 'kitty')['state'] == 'available'
    assert helper.setup(config, 'kitty', EXTRAS)['state'] == 'following'
    text = (kitty / 'kitty.conf').read_text()
    assert text.splitlines()[-2:] == ['# pistachio-shell theming: follows the shell\'s Colours', 'include pistachio-shared.conf'], text
    assert (kitty / 'pistachio-noir.conf').exists() and (kitty / 'noir.conf').exists() and (kitty / 'pistachio-shared.conf').exists()
    assert len(backups(kitty)) == 1
    print('fresh_kitty_is_available_then_following: passed')
    helper.setup(config, 'kitty', EXTRAS)
    assert (kitty / 'kitty.conf').read_text().count('pistachio-shell theming') == 1 and (kitty / 'kitty.conf').read_text().count('include pistachio-shared.conf') == 1
    print('setup_twice_is_one_line: passed')
    assert helper.undo(config, 'kitty')['state'] == 'available'
    assert (kitty / 'kitty.conf').read_text() == original and not (kitty / 'pistachio-shared.conf').exists()
    print('kitty_undo_restores_bytes: passed')
    kitten = 'include current-theme.conf\nfont_size 12\n'
    (kitty / 'kitty.conf').write_text(kitten)
    assert state(config, 'kitty')['state'] == 'own' and (kitty / 'kitty.conf').read_text() == kitten
    (kitty / 'kitty.conf').write_text('foreground #ffffff\n')
    assert state(config, 'kitty')['state'] == 'own'
    print('kitty_kitten_theme_is_own: passed')
    owner = '# mine\ninclude pistachio-shared.conf\nfont_size 12\n'
    (kitty / 'kitty.conf').write_text(owner)
    assert state(config, 'kitty')['state'] == 'following'
    helper.setup(config, 'kitty', EXTRAS)
    assert (kitty / 'kitty.conf').read_text() == owner
    print('owner_style_wired_kitty_is_following: passed')
    (kitty / 'pistachio-shared.conf').write_text('include noir.conf\n')
    helper.undo(config, 'kitty')
    assert (kitty / 'kitty.conf').read_text() == '# mine\ninclude pistachio-noir.conf\nfont_size 12\n', (kitty / 'kitty.conf').read_text()
    print('kitty_legacy_undo: passed')

    nvim = config / 'nvim'; nvim.mkdir()
    plain = 'vim.opt.number = true\nrequire("lazy").setup({})\n'
    (nvim / 'init.lua').write_text(plain)
    assert state(config, 'neovim')['state'] == 'available'
    assert helper.setup(config, 'neovim', EXTRAS)['state'] == 'following'
    lines = (nvim / 'init.lua').read_text().splitlines()
    assert lines[-1] == 'pcall(function() require("pistachio-shared").setup() end) -- pistachio-shell theming', lines
    assert (nvim / 'colors/pistachio-noir.lua').exists() and (nvim / 'lua/pistachio-shared.lua').exists()
    assert helper.undo(config, 'neovim')['state'] == 'available' and (nvim / 'init.lua').read_text() == plain
    print('neovim_without_colorscheme_line: passed')
    (nvim / 'init.lua').write_text('vim.cmd("colorscheme tokyonight")\n')
    assert state(config, 'neovim')['state'] == 'own'
    print('neovim_own_colorscheme: passed')
    (nvim / 'init.lua').write_text('vim.opt.number = true\nrequire("pistachio-shared").setup()\n')
    assert state(config, 'neovim')['state'] == 'following'
    helper.undo(config, 'neovim')
    assert (nvim / 'init.lua').read_text() == 'vim.opt.number = true\nvim.cmd("colorscheme pistachio-noir")\n'
    print('neovim_legacy_undo: passed')
    (nvim / 'init.lua').unlink(); (nvim / 'init.vim').write_text('colorscheme desert\n')
    s = state(config, 'neovim')
    assert s['state'] == 'unsupported' and 'init.vim' in s['detail'], s
    print('neovim_init_vim_only: passed')

    (kitty / 'kitty.conf').write_text(original)
    real_read = helper.read_config
    saved = []
    def racing(path):
        text = real_read(path)
        if path.name == 'kitty.conf':
            saved.append(1)
            if len(saved) == 2:  # after setup's own read, before it writes: the user saves
                path.write_text(text + 'font_size 14\n')
        return text
    with patch.object(helper, 'read_config', racing):
        s = helper.setup(config, 'kitty', EXTRAS)
    assert s['state'] == 'unsupported' and 'changed' in s['detail'], s
    assert (kitty / 'kitty.conf').read_text() == original + 'font_size 14\n'
    print('changed_file_left_alone: passed')

with tempfile.TemporaryDirectory() as folder, patch.object(helper.shutil, 'which', return_value=None):
    assert {a['id']: a['state'] for a in helper.status(Path(folder))} == {'kitty': 'missing', 'neovim': 'missing'}
    print('missing_apps: passed')

with tempfile.TemporaryDirectory() as folder:
    out = subprocess.run([sys.executable, '-I', str(HELPER), 'status'], env=dict(os.environ, XDG_CONFIG_HOME=folder),
                         capture_output=True, text=True, check=True).stdout.strip().splitlines()
    assert len(out) == 1 and {a['id'] for a in json.loads(out[0])['apps']} == {'kitty', 'neovim'}, out
    print('cli_status: passed')

# --- review fixes (19 November 2026) ---
with tempfile.TemporaryDirectory() as folder, patch.object(helper.shutil, 'which', return_value='/usr/bin/x'), \
        patch.object(helper.subprocess, 'run') as run:
    run.return_value.returncode = 0
    config = Path(folder)
    nvim = config / 'nvim'; nvim.mkdir()
    for text in ['vim.cmd.colorscheme("tokyonight")\n', "vim.cmd.colorscheme 'gruvbox'\n", 'vim.cmd("colorscheme catppuccin")\n']:
        (nvim / 'init.lua').write_text(text)
        assert state(config, 'neovim')['state'] == 'own', text
    (nvim / 'init.lua').write_text('require("config.lazy")\n')
    (nvim / 'lua/plugins').mkdir(parents=True)
    (nvim / 'lua/plugins/theme.lua').write_text('return { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } }\n')
    assert state(config, 'neovim')['state'] == 'own'
    print('neovim_colorscheme_in_lua_tree_is_own: passed')
    (nvim / 'lua/plugins/theme.lua').unlink()
    (nvim / 'init.lua').write_text('vim.cmd.colorscheme("tokyonight")\n')
    s = helper.setup(config, 'neovim', EXTRAS)
    assert s['state'] == 'own' and (nvim / 'init.lua').read_text() == 'vim.cmd.colorscheme("tokyonight")\n'
    assert helper.setup(config, 'neovim', EXTRAS, force=True)['state'] == 'following'
    print('quiet_setup_skips_own_force_wires: passed')

    kitty = config / 'kitty'; kitty.mkdir()
    (kitty / 'kitty.conf').write_text('include pistachio-noir.conf\nfont_size 12\n')
    assert state(config, 'kitty')['state'] == 'available'
    (kitty / 'kitty.conf').write_text('include noir.conf\n')
    assert state(config, 'kitty')['state'] == 'available'
    print('our_own_theme_files_are_not_a_conflict: passed')

    real = config / 'dotfiles/kitty.conf'; real.parent.mkdir(); real.write_text('font_size 12\n')
    (kitty / 'kitty.conf').unlink(); (kitty / 'kitty.conf').symlink_to(real)
    s = state(config, 'kitty')
    assert s['state'] == 'unsupported' and 'link' in s['detail'], s
    helper.setup(config, 'kitty', EXTRAS, force=True)
    assert (kitty / 'kitty.conf').is_symlink() and real.read_text() == 'font_size 12\n'
    print('symlinked_config_is_left_alone: passed')

with tempfile.TemporaryDirectory() as folder:
    nvim = Path(folder) / 'nvim'; nvim.mkdir(); (nvim / 'init.lua').write_text('x = 1\n')
    os.chmod(nvim / 'init.lua', 0o444); os.chmod(nvim, 0o555)
    try:
        out = subprocess.run([sys.executable, '-I', str(HELPER), 'setup', 'neovim'], env=dict(os.environ, XDG_CONFIG_HOME=folder),
                             capture_output=True, text=True).stdout.strip()
        app = next(a for a in json.loads(out)['apps'] if a['id'] == 'neovim')
        assert app['state'] == 'unsupported' and app['detail'], app
    finally:
        os.chmod(nvim, 0o755); os.chmod(nvim / 'init.lua', 0o644)
    print('cli_reports_why_setup_failed: passed')

# Kitty reads no comment after an include on the same line (19 November 2026: the first marked line was
# skipped by Kitty as a missing file); the old line is repaired by setup and removed by undo
with tempfile.TemporaryDirectory() as folder, patch.object(helper.shutil, 'which', return_value='/usr/bin/x'), \
        patch.object(helper.subprocess, 'run') as run:
    run.return_value.returncode = 0
    config = Path(folder); kitty = config / 'kitty'; kitty.mkdir()
    broken = 'include pistachio-noir.conf\nfont_size 12\ninclude pistachio-shared.conf  # pistachio-shell theming\n'
    (kitty / 'kitty.conf').write_text(broken)
    assert state(config, 'kitty')['state'] == 'available'
    helper.setup(config, 'kitty', EXTRAS)
    text = (kitty / 'kitty.conf').read_text()
    assert '  # pistachio-shell theming' not in text and text.endswith("# pistachio-shell theming: follows the shell's Colours\ninclude pistachio-shared.conf\n"), text
    helper.undo(config, 'kitty')
    assert (kitty / 'kitty.conf').read_text() == 'include pistachio-noir.conf\nfont_size 12\n'
    (kitty / 'kitty.conf').write_text(broken); helper.undo(config, 'kitty')
    assert (kitty / 'kitty.conf').read_text() == 'include pistachio-noir.conf\nfont_size 12\n'
    print('kitty_old_marked_line_repaired: passed')
import shutil as _sh
if _sh.which('kitty'):  # only where Kitty is installed: its own loader must read our include
    keep = tempfile.TemporaryDirectory(); folder = keep.name
    with patch.object(helper.subprocess, 'run') as run:
        run.return_value.returncode = 0
        config = Path(folder); (config / 'kitty').mkdir(); (config / 'kitty/kitty.conf').write_text('include pistachio-noir.conf\n')
        (config / 'pistachio').mkdir(); (config / 'pistachio/shared-theme').write_text('noir\n')
        helper.setup(config, 'kitty', EXTRAS)
        conf = str(config / 'kitty/kitty.conf')
    probe = 'from kitty.config import load_config; o=load_config(%r); print(o.background)' % conf
    out = subprocess.run(['kitty', '+runpy', probe], capture_output=True, text=True, timeout=20)
    keep.cleanup()
    assert 'Could not find included' not in out.stdout + out.stderr and 'Color(17, 17, 17)' in out.stdout, out.stdout + out.stderr
    print('kitty_itself_reads_the_setup_as_noir: passed')

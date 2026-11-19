#!/usr/bin/env python3
"""Publish the shell's colour choice, and set apps up to follow it (theming integration).

  shared-theme.py publish SCHEME   (or just SCHEME)   write the choice; switch wired apps (Kitty) live
  shared-theme.py status                              {"apps": [{id, name, state, detail}]}
  shared-theme.py setup APP | use APP | undo APP      act (setup leaves an own theme alone; use doesn't), then status

States: following (wired up), own (the app has its own theme: asked first), available (can be set up),
missing (not installed), unsupported (detail says why). Owner's call, 19 November 2026: the shell
wires apps itself behind one switch, never over a user's own theme without asking, and undo removes
only the lines it added (marked), so the app's own settings apply again. Python for now; this moves
into the Rust CLI later.
"""
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import sys
import subprocess
import tempfile

MARK_LUA = ' -- pistachio-shell theming'
# Kitty takes no comment after an include on the same line (it read the whole rest as the file name and
# skipped it, 19 November 2026), so its marker is a comment line of its own right above a plain include
KITTY_MARK = "# pistachio-shell theming: follows the shell's Colours"
KITTY_BLOCK = KITTY_MARK + '\ninclude pistachio-shared.conf\n'
KITTY_OLD = 'include pistachio-shared.conf  # pistachio-shell theming'  # the first, broken form
NVIM_LINE = 'pcall(function() require("pistachio-shared").setup() end)' + MARK_LUA
LEGACY_NVIM = 'require("pistachio-shared").setup()'
LEGACY_RESTORE = 'vim.cmd("colorscheme pistachio-noir")'


class Changed(Exception):
    pass


def write_atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.shared-theme-')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o7777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_config(path):
    return path.read_text()


def rewrite(path, before, after):
    """Back up and replace a config the shell read as `before`; refuse if it changed meanwhile."""
    if path.read_text() != before:
        raise Changed()
    shutil.copy2(path, path.with_name(path.name + '.pistachio-bak-' + datetime.now().strftime('%Y%m%d-%H%M%S')))
    write_atomic(path, after)


def copy_in(source, target):
    """Put a theme file in place; a different file already there is backed up first."""
    if target.exists() and target.read_bytes() == source.read_bytes():
        return
    if target.exists():
        shutil.copy2(target, target.with_name(target.name + '.pistachio-bak-' + datetime.now().strftime('%Y%m%d-%H%M%S')))
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def reload_kitty():
    result = subprocess.run(['pkill', '-USR1', '-u', str(os.getuid()), '-x', 'kitty'])
    if result.returncode not in (0, 1):
        print('Could not reload Kitty configuration', file=sys.stderr)


def kitty_scheme_include(config):
    path = config / 'kitty/pistachio-shared.conf'
    return path


# --- Kitty -------------------------------------------------------------------------------------
# a theme of the user's own: colour lines, or an include of a file that isn't one of ours
KITTY_COLOURS = re.compile(r'^\s*((foreground|background|color\d{1,3})\s|(glob|env)?include\s+(?!(pistachio-shared|pistachio-noir|noir)\.conf\b)\S)')
LINKED = 'is a symbolic link (a dotfile manager?); set it up by hand'


def kitty_status(config):
    conf = config / 'kitty/kitty.conf'
    if conf.is_symlink():
        return 'unsupported', 'kitty.conf ' + LINKED
    if not conf.exists():
        return ('available', '') if (config / 'kitty').is_dir() or shutil.which('kitty') else ('missing', '')
    lines = read_config(conf).splitlines()
    if any(l.strip() == 'include pistachio-shared.conf' for l in lines):
        return 'following', ''
    if any(KITTY_COLOURS.match(l) for l in lines):
        return 'own', ''
    return 'available', ''


def kitty_setup(config, extras, scheme, force=False):
    folder = config / 'kitty'
    conf = folder / 'kitty.conf'
    state = kitty_status(config)[0]
    if state in ('following', 'unsupported', 'missing') or state == 'own' and not force:
        return
    before = read_config(conf) if conf.exists() else None
    copy_in(extras / 'kitty-pistachio-noir.conf', folder / 'pistachio-noir.conf')
    copy_in(extras / 'kitty-noir.conf', folder / 'noir.conf')
    write_atomic(folder / 'pistachio-shared.conf', 'include ' + ('noir.conf' if scheme == 'noir' else 'pistachio-noir.conf') + '\n')
    if before is None:
        write_atomic(conf, KITTY_BLOCK)
    else:
        kept = ''.join(l for l in before.splitlines(keepends=True) if l.rstrip('\n').strip() != KITTY_OLD)
        rewrite(conf, before, kept + ('' if kept.endswith('\n') or not kept else '\n') + KITTY_BLOCK)
    reload_kitty()


def kitty_undo(config):
    conf = config / 'kitty/kitty.conf'
    if conf.exists():
        before = read_config(conf)
        kept = []
        ours = False  # the line after our marker is our include
        for line in before.splitlines(keepends=True):
            bare = line.rstrip('\n').strip()
            if bare == KITTY_MARK:
                ours = True
                continue
            if bare == KITTY_OLD or ours and bare == 'include pistachio-shared.conf':
                ours = False
                continue
            ours = False
            if bare == 'include pistachio-shared.conf':  # the hand install of 18 November replaced this line
                line = line.replace('include pistachio-shared.conf', 'include pistachio-noir.conf')
            kept.append(line)
        if ''.join(kept) != before:
            rewrite(conf, before, ''.join(kept))
    include = config / 'kitty/pistachio-shared.conf'
    if include.exists():
        include.unlink()
    reload_kitty()


# --- Neovim ------------------------------------------------------------------------------------
def nvim_status(config):
    folder = config / 'nvim'
    init = folder / 'init.lua'
    if init.is_symlink() or folder.is_symlink():
        return 'unsupported', ('init.lua ' if init.is_symlink() else 'the nvim folder ') + LINKED
    if not init.exists():
        if (folder / 'init.vim').exists():
            return 'unsupported', 'Neovim is set up with init.vim; only init.lua is supported'
        return ('available', '') if folder.is_dir() or shutil.which('nvim') else ('missing', '')
    text = read_config(init)
    if any('require("pistachio-shared").setup()' in l and not l.lstrip().startswith('--') for l in text.splitlines()):
        return 'following', ''
    # `colorscheme x`, vim.cmd.colorscheme("x") / 'x', LazyVim's opts = { colorscheme = "x" }, in init.lua or
    # any Lua file under lua/ (plugin specs); our own colors/ and pistachio-shared.lua don't count
    sources = [text] + [read_config(p) for p in sorted((folder / 'lua').rglob('*.lua'))
                        if p.name != 'pistachio-shared.lua'] if (folder / 'lua').is_dir() else [text]
    for source in sources:
        for line in source.splitlines():
            if line.lstrip().startswith('--'):
                continue
            for m in COLORSCHEME.finditer(line):
                if m.group(1) != 'pistachio-noir':
                    return 'own', ''
    return 'available', ''


COLORSCHEME = re.compile(r'''colorscheme(?:\s*=\s*|\s*\(\s*|\s+)["']?([\w.-]+)''')


def nvim_setup(config, extras, _scheme, force=False):
    folder = config / 'nvim'
    init = folder / 'init.lua'
    state = nvim_status(config)[0]
    if state in ('following', 'unsupported', 'missing') or state == 'own' and not force:
        return
    before = read_config(init) if init.exists() else None
    copy_in(extras / 'neovim/colors/pistachio-noir.lua', folder / 'colors/pistachio-noir.lua')
    copy_in(extras / 'neovim/lua/pistachio-shared.lua', folder / 'lua/pistachio-shared.lua')
    if before is None:
        write_atomic(init, NVIM_LINE + '\n')
    else:
        rewrite(init, before, before + ('' if before.endswith('\n') or not before else '\n') + NVIM_LINE + '\n')


def nvim_undo(config):
    init = config / 'nvim/init.lua'
    if not init.exists():
        return
    before = read_config(init)
    out = []
    for line in before.splitlines(keepends=True):
        bare = line.rstrip('\n')
        if bare.endswith(MARK_LUA):
            continue
        if bare.strip() == LEGACY_NVIM:  # the hand install of 18 November replaced this line
            line = line.replace(LEGACY_NVIM, LEGACY_RESTORE)
        out.append(line)
    if ''.join(out) != before:
        rewrite(init, before, ''.join(out))


APPS = [
    {'id': 'kitty', 'name': 'Kitty', 'status': kitty_status, 'setup': kitty_setup, 'undo': kitty_undo},
    {'id': 'neovim', 'name': 'Neovim', 'status': nvim_status, 'setup': nvim_setup, 'undo': nvim_undo},
]


def entry(app, config):
    try:
        state, detail = app['status'](config)
    except OSError as e:
        state, detail = 'unsupported', str(e.strerror or e)
    return {'id': app['id'], 'name': app['name'], 'state': state, 'detail': detail}


def status(config):
    return [entry(app, config) for app in APPS]


def current_scheme(config):
    try:
        value = (config / 'pistachio/shared-theme').read_text().strip()
    except OSError:
        value = ''
    return value if value in ('pistachio', 'noir') else 'pistachio'


def act(config, app_id, action, extras=None, force=False):
    app = next(a for a in APPS if a['id'] == app_id)
    try:
        if action == 'setup':
            app['setup'](config, extras, current_scheme(config), force)
        else:
            app['undo'](config)
    except Changed:
        return {'id': app['id'], 'name': app['name'], 'state': 'unsupported', 'detail': 'its config changed while reading; try again'}
    except OSError as e:
        return {'id': app['id'], 'name': app['name'], 'state': 'unsupported', 'detail': str(e.strerror or e)}
    return entry(app, config)


def setup(config, app_id, extras, force=False):
    """Quietly wire an app up (an `own` theme is left alone), or with `force` (Use Pistachio) over its theme."""
    return act(config, app_id, 'setup', extras, force)


def undo(config, app_id):
    return act(config, app_id, 'undo')


def publish(path, scheme):
    if scheme not in ('pistachio', 'noir'):
        raise ValueError('invalid colour scheme')
    write_atomic(path, scheme + '\n')
    kitty = path.parent.parent / 'kitty/pistachio-shared.conf'
    if kitty.exists():
        content = 'include ' + ('noir.conf' if scheme == 'noir' else 'pistachio-noir.conf') + '\n'
        if kitty.read_text() != content:
            write_atomic(kitty, content)
            reload_kitty()


if __name__ == '__main__':
    config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    extras = Path(__file__).resolve().parents[2] / 'extras'
    args = sys.argv[1:]
    try:
        if args and args[0] in ('pistachio', 'noir'):
            publish(config / 'pistachio/shared-theme', args[0])
            sys.exit(0)
        if args[:1] == ['publish'] and len(args) == 2:
            publish(config / 'pistachio/shared-theme', args[1])
        result = None
        if args[:1] in (['setup'], ['use'], ['undo']) and len(args) == 2 and args[1] in [a['id'] for a in APPS]:
            result = act(config, args[1], 'undo' if args[0] == 'undo' else 'setup', extras, args[0] == 'use')
        elif args[:1] != ['publish'] and args != ['status']:
            raise ValueError('usage: shared-theme.py publish SCHEME | status | setup APP | use APP | undo APP')
        apps = status(config)
        if result and result['state'] == 'unsupported':  # keep the reason the action gave (e.g. changed meanwhile)
            apps = [result if a['id'] == result['id'] else a for a in apps]
        print(json.dumps({'apps': apps}), flush=True)
    except (ValueError, OSError) as e:
        print(json.dumps({'error': str(e)}), flush=True)
        sys.exit(1)

import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    folder = Path(temp)
    theme = folder / 'pistachio' / 'shared-theme'
    theme.parent.mkdir()
    theme.write_text('pistachio\n')
    lua = folder / 'test.lua'
    lua.write_text('''
vim.opt.runtimepath:prepend(vim.env.TEST_NVIM_RUNTIME)
require('pistachio-shared').setup()
local function color(group, key) return vim.api.nvim_get_hl(0, {name=group})[key] end
assert(color('Normal', 'bg') == 0x15170f)
assert(color('String', 'fg') == 0x9fd88a)
local function write(value)
  local path=vim.env.XDG_CONFIG_HOME..'/pistachio/shared-theme'
  local f=assert(io.open(path..'.tmp','w')); f:write(value); f:close(); assert(os.rename(path..'.tmp',path))
end
write('noir\\n')
assert(vim.wait(3000, function() return color('Normal','bg') == 0x111111 end, 25), 'Noir did not load')
assert(color('String','fg') == 0xa9b89a, 'Noir strings keep a muted sage')
assert(color('Function','fg') == 0x9aaab8 and color('Type','fg') == 0xc8b892 and color('Keyword','fg') == 0xb2a4be, 'Noir code keeps muted hues')
assert(color('Cursor','bg') == 0xbdbdbd and color('PmenuSel','bg') == 0xbdbdbd, 'Noir UI stays grey')
write('pistachio\\n')
assert(vim.wait(3000, function() return color('Normal','bg') == 0x15170f end, 25), 'Pistachio did not return')
assert(color('String','fg') == 0x9fd88a, 'Pistachio strings are pistachio again')
''')
    env = dict(os.environ, XDG_CONFIG_HOME=str(folder), XDG_STATE_HOME=str(folder / 'state'),
               XDG_CACHE_HOME=str(folder / 'cache'), XDG_DATA_HOME=str(folder / 'data'),
               TEST_NVIM_RUNTIME=str(root / 'integrations/neovim'))
    subprocess.run(['nvim', '--headless', '-u', 'NONE', '-l', str(lua)], env=env, check=True, timeout=10)
print('ok: Neovim follows the shared theme live')

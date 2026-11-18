#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/nvim
backup_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/nvim-backup-shared-theme-$(date +%Y%m%d-%H%M%S)
[ -f "$config_dir/init.lua" ] && [ -f "$config_dir/colors/pistachio-noir.lua" ] || { echo 'Neovim init.lua or existing theme not found' >&2; exit 1; }
grep -Fxq 'vim.cmd("colorscheme pistachio-noir")' "$config_dir/init.lua" || { echo 'Expected colorscheme line not found; nothing changed' >&2; exit 1; }
mkdir "$backup_dir"
cp -a "$config_dir/init.lua" "$config_dir/colors/pistachio-noir.lua" "$backup_dir/"
if [ -f "$config_dir/lua/pistachio-shared.lua" ]; then cp -a "$config_dir/lua/pistachio-shared.lua" "$backup_dir/"; fi
mkdir -p "$config_dir/lua"
cp "$source_dir/colors/pistachio-noir.lua" "$config_dir/colors/pistachio-noir.lua"
cp "$source_dir/lua/pistachio-shared.lua" "$config_dir/lua/pistachio-shared.lua"
python3 - "$config_dir/init.lua" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
path.write_text(text.replace('vim.cmd("colorscheme pistachio-noir")', 'require("pistachio-shared").setup()', 1))
PY
printf 'Backup: %s\n' "$backup_dir"

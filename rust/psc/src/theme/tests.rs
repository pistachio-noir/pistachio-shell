//! Every case of the old tests/shared-theme.test.py, against the Rust port. Temporary config
//! folders, a stand-in PATH and a counting stand-in for Kitty's reload: no real app is touched.
use super::*;
use std::cell::Cell;

struct T { dir: PathBuf, bin: PathBuf }

impl T {
    fn new(name: &str, installed: &[&str]) -> T {
        let dir = std::env::temp_dir().join(format!("psc-theme-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let bin = dir.join("bin");
        std::fs::create_dir_all(&bin).unwrap();
        for p in installed {
            std::fs::write(bin.join(p), "#!/bin/sh\n").unwrap();
            std::fs::set_permissions(bin.join(p), std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        }
        T { dir: dir.join("config"), bin }
    }
    fn file(&self, p: &str) -> PathBuf { self.dir.join(p) }
    fn put(&self, p: &str, text: &str) { std::fs::create_dir_all(self.file(p).parent().unwrap()).unwrap(); std::fs::write(self.file(p), text).unwrap(); }
    fn read(&self, p: &str) -> String { std::fs::read_to_string(self.file(p)).unwrap_or_default() }
    fn backups(&self, folder: &str) -> usize {
        std::fs::read_dir(self.file(folder)).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().contains(".pistachio-bak-")).count()
    }
}

impl Drop for T {
    fn drop(&mut self) { let _ = std::fs::remove_dir_all(self.dir.parent().unwrap()); }
}

fn state(t: &T, env: &Env, app: &str) -> Value {
    status(&t.dir, env).into_iter().find(|a| a["id"] == app).unwrap()
}

#[test]
fn publication_and_kitty_reload() {
    let t = T::new("publish", &[]);
    let reloads = Cell::new(0);
    let env = Env { path: t.bin.clone().into(), reload: &|| reloads.set(reloads.get() + 1) };
    let path = t.file("pistachio/shared-theme");
    publish(&path, "noir", &env).unwrap();
    assert_eq!(t.read("pistachio/shared-theme"), "noir\n");
    publish(&path, "pistachio", &env).unwrap();
    assert!(publish(&path, "invalid", &env).is_err());
    assert_eq!(t.read("pistachio/shared-theme"), "pistachio\n");
    t.put("kitty/pistachio-shared.conf", "include pistachio-noir.conf\n");
    publish(&path, "noir", &env).unwrap();
    assert_eq!(t.read("kitty/pistachio-shared.conf"), kitty_scheme("noir"));
    assert!(kitty_scheme("noir").contains("background") && !kitty_scheme("noir").lines().any(|l| l.trim_start().starts_with("include")));
    assert_eq!(reloads.get(), 1);
    publish(&path, "noir", &env).unwrap();
    assert_eq!(reloads.get(), 1, "no reload when nothing changed");
    publish(&path, "pistachio", &env).unwrap();
    assert_eq!(t.read("kitty/pistachio-shared.conf"), kitty_scheme("pistachio"));
    assert_eq!(reloads.get(), 2);
}

#[test]
fn kitty_setup_undo_and_states() {
    let t = T::new("kitty", &["kitty", "nvim"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    let original = "font_size 12\nbackground_opacity 0.9\n";
    t.put("kitty/kitty.conf", original);
    assert_eq!(state(&t, &env, "kitty")["state"], "available");
    assert_eq!(act(&t.dir, &env, "kitty", "setup").unwrap()["state"], "following");
    let text = t.read("kitty/kitty.conf");
    assert!(text.ends_with(&format!("{KITTY_MARK}\n{KITTY_INCLUDE}\n")), "{text}");
    assert!(t.file("kitty/pistachio-noir.conf").exists() && t.file("kitty/noir.conf").exists() && t.file("kitty/pistachio-shared.conf").exists());
    assert_eq!(t.backups("kitty"), 1);
    act(&t.dir, &env, "kitty", "setup");
    let text = t.read("kitty/kitty.conf");
    assert_eq!((text.matches("pistachio-shell theming").count(), text.matches(KITTY_INCLUDE).count()), (1, 1), "setup twice is one block");
    assert_eq!(act(&t.dir, &env, "kitty", "undo").unwrap()["state"], "available");
    assert_eq!(t.read("kitty/kitty.conf"), original, "undo restores the bytes");
    assert!(!t.file("kitty/pistachio-shared.conf").exists());
    let kitten = "include current-theme.conf\nfont_size 12\n";
    t.put("kitty/kitty.conf", kitten);
    assert_eq!(state(&t, &env, "kitty")["state"], "own");
    assert_eq!(t.read("kitty/kitty.conf"), kitten, "status leaves it untouched");
    t.put("kitty/kitty.conf", "foreground #ffffff\n");
    assert_eq!(state(&t, &env, "kitty")["state"], "own");
    let owner = "# mine\ninclude pistachio-shared.conf\nfont_size 12\n";
    t.put("kitty/kitty.conf", owner);
    assert_eq!(state(&t, &env, "kitty")["state"], "following");
    act(&t.dir, &env, "kitty", "setup");
    assert_eq!(t.read("kitty/kitty.conf"), owner, "already wired: setup changes nothing");
    t.put("kitty/pistachio-shared.conf", "include noir.conf\n");
    act(&t.dir, &env, "kitty", "undo");
    assert_eq!(t.read("kitty/kitty.conf"), "# mine\ninclude pistachio-noir.conf\nfont_size 12\n", "the hand-installed line goes back");
    for ours in ["include pistachio-noir.conf\nfont_size 12\n", "include noir.conf\n"] {
        t.put("kitty/kitty.conf", ours);
        assert_eq!(state(&t, &env, "kitty")["state"], "available", "our own theme files aren't a conflict");
    }
    assert!(kitty_colour_line("color255 #000") && !kitty_colour_line("background_opacity 0.5") && kitty_colour_line("globinclude themes/*.conf"));
}

#[test]
fn kitty_old_marked_line_repaired() {
    let t = T::new("kittyold", &["kitty"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    let broken = "include pistachio-noir.conf\nfont_size 12\ninclude pistachio-shared.conf  # pistachio-shell theming\n";
    t.put("kitty/kitty.conf", broken);
    assert_eq!(state(&t, &env, "kitty")["state"], "available");
    act(&t.dir, &env, "kitty", "setup");
    let text = t.read("kitty/kitty.conf");
    assert!(!text.contains("  # pistachio-shell theming") && text.ends_with(&format!("{KITTY_MARK}\n{KITTY_INCLUDE}\n")), "{text}");
    act(&t.dir, &env, "kitty", "undo");
    assert_eq!(t.read("kitty/kitty.conf"), "include pistachio-noir.conf\nfont_size 12\n");
    t.put("kitty/kitty.conf", broken);
    act(&t.dir, &env, "kitty", "undo");
    assert_eq!(t.read("kitty/kitty.conf"), "include pistachio-noir.conf\nfont_size 12\n");
}

#[test]
fn neovim_setup_undo_and_states() {
    let t = T::new("nvim", &["kitty", "nvim"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    let plain = "vim.opt.number = true\nrequire(\"lazy\").setup({})\n";
    t.put("nvim/init.lua", plain);
    assert_eq!(state(&t, &env, "neovim")["state"], "available");
    assert_eq!(act(&t.dir, &env, "neovim", "setup").unwrap()["state"], "following");
    assert_eq!(t.read("nvim/init.lua").lines().last().unwrap(), NVIM_LINE);
    assert!(t.file("nvim/colors/pistachio-noir.lua").exists() && t.file("nvim/lua/pistachio-shared.lua").exists());
    assert_eq!(act(&t.dir, &env, "neovim", "undo").unwrap()["state"], "available");
    assert_eq!(t.read("nvim/init.lua"), plain);
    for own in ["vim.cmd(\"colorscheme tokyonight\")\n", "vim.cmd.colorscheme(\"tokyonight\")\n", "vim.cmd.colorscheme 'gruvbox'\n"] {
        t.put("nvim/init.lua", own);
        assert_eq!(state(&t, &env, "neovim")["state"], "own", "{own}");
    }
    t.put("nvim/init.lua", "-- vim.cmd(\"colorscheme tokyonight\")\n");
    assert_eq!(state(&t, &env, "neovim")["state"], "available", "a commented-out colorscheme doesn't count");
    t.put("nvim/init.lua", "require(\"config.lazy\")\n");
    t.put("nvim/lua/plugins/theme.lua", "return { \"LazyVim/LazyVim\", opts = { colorscheme = \"catppuccin\" } }\n");
    assert_eq!(state(&t, &env, "neovim")["state"], "own", "LazyVim's opts in lua/");
    std::fs::remove_file(t.file("nvim/lua/plugins/theme.lua")).unwrap();
    t.put("nvim/init.lua", "vim.cmd.colorscheme(\"tokyonight\")\n");
    assert_eq!(act(&t.dir, &env, "neovim", "setup").unwrap()["state"], "own", "quiet setup leaves an own theme alone");
    assert_eq!(t.read("nvim/init.lua"), "vim.cmd.colorscheme(\"tokyonight\")\n");
    assert_eq!(act(&t.dir, &env, "neovim", "use").unwrap()["state"], "following", "Use Pistachio wires it");
    t.put("nvim/init.lua", "vim.opt.number = true\nrequire(\"pistachio-shared\").setup()\n");
    assert_eq!(state(&t, &env, "neovim")["state"], "following");
    act(&t.dir, &env, "neovim", "undo");
    assert_eq!(t.read("nvim/init.lua"), "vim.opt.number = true\nvim.cmd(\"colorscheme pistachio-noir\")\n", "legacy line restored");
    std::fs::remove_file(t.file("nvim/init.lua")).unwrap();
    t.put("nvim/init.vim", "colorscheme desert\n");
    let s = state(&t, &env, "neovim");
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("init.vim"), "{s}");
}

#[test]
fn changed_file_left_alone() {
    let t = T::new("race", &["kitty"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    let original = "font_size 12\n";
    t.put("kitty/kitty.conf", original);
    let conf = t.file("kitty/kitty.conf");
    BEFORE_WRITE.with(|h| *h.borrow_mut() = Some(Box::new(move || {
        let text = std::fs::read_to_string(&conf).unwrap();
        std::fs::write(&conf, text + "font_size 14\n").unwrap(); // the user saves in between
    })));
    let s = act(&t.dir, &env, "kitty", "setup").unwrap();
    BEFORE_WRITE.with(|h| *h.borrow_mut() = None);
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("changed"), "{s}");
    assert_eq!(t.read("kitty/kitty.conf"), "font_size 12\nfont_size 14\n");
}

#[test]
fn missing_and_symlinked() {
    let t = T::new("missing", &[]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    std::fs::create_dir_all(&t.dir).unwrap();
    let states: Vec<_> = status(&t.dir, &env).iter().map(|a| a["state"].as_str().unwrap().to_string()).collect();
    assert_eq!(states, ["missing", "missing"]);
    t.put("dotfiles/kitty.conf", "font_size 12\n");
    std::fs::create_dir_all(t.file("kitty")).unwrap();
    std::os::unix::fs::symlink(t.file("dotfiles/kitty.conf"), t.file("kitty/kitty.conf")).unwrap();
    let s = state(&t, &env, "kitty");
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("link"), "{s}");
    act(&t.dir, &env, "kitty", "use");
    assert!(t.file("kitty/kitty.conf").is_symlink() && t.read("dotfiles/kitty.conf") == "font_size 12\n");
}

#[test]
fn setup_failure_says_why() {
    let t = T::new("readonly", &["nvim"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    t.put("nvim/init.lua", "x = 1\n");
    std::fs::set_permissions(t.file("nvim"), std::os::unix::fs::PermissionsExt::from_mode(0o555)).unwrap();
    let s = act(&t.dir, &env, "neovim", "setup").unwrap();
    std::fs::set_permissions(t.file("nvim"), std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    assert!(s["state"] == "unsupported" && !s["detail"].as_str().unwrap().is_empty(), "{s}");
}

#[test]
fn kitty_itself_reads_the_setup_as_noir() {
    let Some(kitty) = std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).map(|d| d.join("kitty")).find(|p| p.is_file()) else {
        return; // only where Kitty is installed: its own loader must read our include
    };
    let t = T::new("kittyload", &["kitty"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    t.put("kitty/kitty.conf", "include pistachio-noir.conf\n");
    t.put("pistachio/shared-theme", "noir\n");
    act(&t.dir, &env, "kitty", "setup");
    let probe = format!("from kitty.config import load_config; b=[]; o=load_config({:?}, accumulate_bad_lines=b); print(o.background, [str(x.exception) for x in b])", t.file("kitty/kitty.conf"));
    let out = std::process::Command::new(kitty).args(["+runpy", &probe]).output().unwrap();
    let all = String::from_utf8_lossy(&out.stdout).to_string() + &String::from_utf8_lossy(&out.stderr);
    assert!(all.contains("Color(17, 17, 17) []"), "Noir, and no bad lines: {all}");
}

#[test]
fn kitty_itself_reads_pistachio_beside_the_users_own_include() {
    // owner's report, 19 November 2026: Noir → Pistachio Noir showed Kitty's "Errors parsing
    // configuration … pistachio-noir.conf has already been included": kitty.conf includes it itself
    let Some(kitty) = std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).map(|d| d.join("kitty")).find(|p| p.is_file()) else {
        return;
    };
    let t = T::new("kittytwice", &["kitty"]);
    let env = Env { path: t.bin.clone().into(), reload: &|| {} };
    t.put("kitty/kitty.conf", "include pistachio-noir.conf
font_size 12
");
    t.put("pistachio/shared-theme", "noir
");
    act(&t.dir, &env, "kitty", "setup");
    for (scheme, background) in [("pistachio", "Color(21, 23, 15)"), ("noir", "Color(17, 17, 17)"), ("pistachio", "Color(21, 23, 15)")] {
        publish(&t.file("pistachio/shared-theme"), scheme, &env).unwrap();
        // Kitty reports include problems as bad lines (its "Errors parsing configuration" window), not on stderr
        let probe = format!("from kitty.config import load_config; b=[]; o=load_config({:?}, accumulate_bad_lines=b); print(o.background, [str(x.exception) for x in b])", t.file("kitty/kitty.conf"));
        let out = std::process::Command::new(&kitty).args(["+runpy", &probe]).output().unwrap();
        let all = String::from_utf8_lossy(&out.stdout).to_string() + &String::from_utf8_lossy(&out.stderr);
        assert!(all.contains(&format!("{background} []")), "{scheme}, and no bad lines: {all}");
    }
}

#[test]
fn cli_status_is_one_json_line() {
    let dir = std::env::temp_dir().join(format!("psc-theme-cli-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let exe = std::env::current_exe().unwrap();
    let psc = exe.parent().unwrap().parent().unwrap().join("psc");
    if !psc.exists() { let _ = std::fs::remove_dir_all(&dir); return; } // the binary is built by `cargo test` for the integration tests
    let out = std::process::Command::new(psc).args(["theme", "status"]).env("XDG_CONFIG_HOME", &dir).output().unwrap();
    let text = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(lines.len(), 1, "{text}");
    let v: Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(v["apps"].as_array().unwrap().len(), 2);
    let _ = std::fs::remove_dir_all(&dir);
}

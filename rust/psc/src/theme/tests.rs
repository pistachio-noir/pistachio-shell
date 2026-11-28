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
    fn home(&self) -> PathBuf { self.dir.parent().unwrap().join("home") }
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|app| if app == "kitty" { reloads.set(reloads.get() + 1) } };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    std::fs::create_dir_all(&t.dir).unwrap();
    let states: Vec<_> = status(&t.dir, &env).iter().map(|a| a["state"].as_str().unwrap().to_string()).collect();
    assert_eq!(states, ["missing", "missing", "missing", "available", "missing", "missing", "missing", "missing"],
        "kitty, neovim, vscode, gtk (always there), vesktop, btop, yazi, zathura");
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
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
    let out = std::process::Command::new(psc).args(["theme", "status"]).env("XDG_CONFIG_HOME", &dir).env("HOME", &dir).output().unwrap();
    let text = String::from_utf8_lossy(&out.stdout);
    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(lines.len(), 1, "{text}");
    let v: Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(v["apps"].as_array().unwrap().len(), 8);
    let _ = std::fs::remove_dir_all(&dir);
}

// --- VS Code (21 November 2026) -------------------------------------------------------------------

/// A settings.json like a real one (made up here, never the owner's): comments in Polish, a nested
/// object with the same key, the key inside a comment and a string holding `//` and braces.
const VS_SAMPLE: &str = r#"{
    // Pliki: zażółć gęślą jaźń
    "files.trimTrailingWhitespace": true,
    /* "workbench.colorTheme": "not this one" */
    "[cpp]": {
        "workbench.colorTheme": "nested, not top level",
        "editor.formatOnSave": true
    },
    "editor.fontFamily": "'Iosevka // not a comment {', monospace",
    "clangd.arguments": [
        "--background-index", // a trailing comment
    ],
}
"#;

/// An independent JSONC reader (Python's json after removing comments and trailing commas with a
/// regex), when python3 is there: the edited file must still be valid for VS Code.
fn jsonc_ok(text: &str) -> bool {
    let script = r#"import json,re,sys
s=sys.stdin.read()
s=re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/', lambda m: m.group(1) or '', s, flags=re.S)
s=re.sub(r',(\s*[}\]])', r'\1', s)
json.loads(s)"#;
    let Ok(mut child) = std::process::Command::new("python3").args(["-I", "-c", script]).stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).spawn() else { return true };
    std::io::Write::write_all(child.stdin.as_mut().unwrap(), text.as_bytes()).unwrap();
    drop(child.stdin.take());
    child.wait().unwrap().success()
}

#[test]
fn vscode_settings_edits_touch_only_the_theme_line() {
    assert!(jsonc_ok(VS_SAMPLE), "the sample itself");
    assert!(member(VS_SAMPLE, VS_KEY).is_none(), "only a top-level member counts");
    let m = member(VS_SAMPLE, "editor.fontFamily").unwrap();
    assert_eq!(&VS_SAMPLE[m.value.clone()], r#""'Iosevka // not a comment {', monospace""#);
    assert_eq!(&VS_SAMPLE[member(VS_SAMPLE, "files.trimTrailingWhitespace").unwrap().value], "true");

    // none yet: a marked line first in the object; undo gives back every byte
    let with = vs_with_theme(VS_SAMPLE, "Pistachio Noir");
    assert!(with.starts_with("{\n    \"workbench.colorTheme\": \"Pistachio Noir\" /* pistachio-shell theming */,\n    // Pliki"), "{with}");
    assert!(jsonc_ok(&with), "{with}");
    assert_eq!(vs_without_theme(&with).unwrap(), VS_SAMPLE);
    // a Colours switch changes only the value
    let m = member(&with, VS_KEY).unwrap();
    let noir = format!("{}{}{}", &with[..m.value.start], quoted("Noir"), &with[m.value.end..]);
    assert_eq!(noir, with.replacen("\"Pistachio Noir\"", "\"Noir\"", 1));
    assert_eq!(vs_with_theme(&with, "Noir"), noir, "setup again on our line only switches it");

    // the user's own theme: replaced, kept in the marker, given back by undo
    let own = VS_SAMPLE.replacen("{\n", "{\n    \"workbench.colorTheme\": \"Default Dark Modern\",\n", 1);
    let used = vs_with_theme(&own, "Pistachio Noir");
    assert!(used.contains("\"workbench.colorTheme\": \"Pistachio Noir\" /* pistachio-shell theming (was \"Default Dark Modern\") */,\n"), "{used}");
    assert!(jsonc_ok(&used));
    assert_eq!(marked(&used, &member(&used, VS_KEY).unwrap()), Some(Some("Default Dark Modern".to_string())));
    assert_eq!(vs_without_theme(&used).unwrap(), own);
    assert!(vs_without_theme(&own).is_none(), "nothing of ours: undo leaves it");

    // small files
    for (before, after) in [
        ("", "{\n    \"workbench.colorTheme\": \"Noir\" /* pistachio-shell theming */\n}\n"),
        ("{}", "{\n    \"workbench.colorTheme\": \"Noir\" /* pistachio-shell theming */}"),
        ("{\n  \"a\": 1\n}\n", "{\n  \"workbench.colorTheme\": \"Noir\" /* pistachio-shell theming */,\n  \"a\": 1\n}\n"),
        // one line: the members after it stay members
        ("{\"a\": 1, \"workbench.colorTheme\": \"X\", \"b\": 2}", "{\"a\": 1, \"workbench.colorTheme\": \"Noir\" /* pistachio-shell theming (was \"X\") */, \"b\": 2}"),
    ] {
        let got = vs_with_theme(before, "Noir");
        assert_eq!(got, after);
        assert!(jsonc_ok(&got), "{got}");
    }
    for before in ["{\n  \"a\": 1\n}\n", "{}", "{\"a\": 1, \"workbench.colorTheme\": \"X\", \"b\": 2}"] {
        assert_eq!(vs_without_theme(&vs_with_theme(before, "Noir")).unwrap(), before, "undo gives back {before:?}");
    }
}

/// A stand-in `code`: records its arguments and keeps the .vsix it was given; exits 1 with FAIL set.
fn fake_code(t: &T, fail: bool) {
    // psc runs it with the test's PATH (only this folder): no dirname, and cp by its full path
    let cp = ["/usr/bin/cp", "/bin/cp"].into_iter().find(|p| Path::new(p).exists()).unwrap();
    let script = format!("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"${{0%/*}}/code.log\"\n{cp} \"$2\" \"${{0%/*}}/got.vsix\"\n{}",
        if fail { "echo 'Failed Installing Extensions: disk full' >&2\nexit 1\n" } else { "exit 0\n" });
    std::fs::write(t.bin.join("code"), script).unwrap();
    std::fs::set_permissions(t.bin.join("code"), std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
}

/// What a real install leaves: the folder and its entry in extensions.json.
fn installed_by_code(t: &T) {
    let folder = t.home().join(".vscode/extensions");
    for (name, data) in VS_FILES {
        let f = folder.join("pistachio-shell.pistachio-noir-1.0.0").join(name);
        std::fs::create_dir_all(f.parent().unwrap()).unwrap();
        std::fs::write(f, data).unwrap();
    }
    // VS Code 1.147 adds its own metadata to the installed package.json (seen in a real install)
    let package = folder.join("pistachio-shell.pistachio-noir-1.0.0/package.json");
    let mut p: Value = serde_json::from_slice(VS_PACKAGE).unwrap();
    p["__metadata"] = json!({"installedTimestamp": 1, "source": "vsix"});
    std::fs::write(package, p.to_string()).unwrap();
    std::fs::write(folder.join("extensions.json"), r#"[{"identifier":{"id":"pistachio-shell.pistachio-noir"},"version":"1.0.0","relativeLocation":"pistachio-shell.pistachio-noir-1.0.0"}]"#).unwrap();
}

#[test]
fn vscode_setup_undo_and_states() {
    let t = T::new("vscode", &[]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    assert_eq!(state(&t, &env, "vscode")["state"], "missing");
    fake_code(&t, false);
    assert_eq!(state(&t, &env, "vscode")["state"], "available", "the code command alone");
    t.put("Code/User/settings.json", VS_SAMPLE);
    let s = act(&t.dir, &env, "vscode", "setup").unwrap();
    let log = std::fs::read_to_string(t.bin.join("code.log")).unwrap_or_else(|_| panic!("code not run: {s}"));
    assert!(log.starts_with("--install-extension ") && log.trim_end().ends_with(".vsix --force"), "{log}");
    let vsix = std::fs::read(t.bin.join("got.vsix")).unwrap();
    assert_eq!(&vsix[..4], b"PK\x03\x04");
    // its own file (the one `code` was given): the other VS Code tests make theirs meanwhile, in the same folder
    let given = log.trim_end().trim_start_matches("--install-extension ").trim_end_matches(" --force");
    assert!(given.ends_with(".vsix") && !Path::new(given).exists(), "the .vsix is removed: {given}");
    assert_eq!(t.read("Code/User/settings.json"), vs_with_theme(VS_SAMPLE, "Pistachio Noir"));
    assert_eq!(t.backups("Code/User"), 1);
    assert_eq!(s["state"], "available", "not following until VS Code recorded the extension");
    installed_by_code(&t);
    assert_eq!(state(&t, &env, "vscode")["state"], "following");
    // a changed theme in a newer psc: installed again
    let theme = t.home().join(".vscode/extensions/pistachio-shell.pistachio-noir-1.0.0/themes/noir.json");
    std::fs::write(&theme, "{}").unwrap();
    assert_eq!(state(&t, &env, "vscode")["state"], "available", "an older theme counts as not installed");
    std::fs::write(&theme, VS_NOIR).unwrap();
    // set up again: nothing to install, nothing to write
    act(&t.dir, &env, "vscode", "setup").unwrap();
    assert_eq!(std::fs::read_to_string(t.bin.join("code.log")).unwrap().lines().count(), 1);

    // a Colours switch is live, without another backup
    t.put("pistachio/shared-theme", "pistachio\n");
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(t.read("Code/User/settings.json"), vs_with_theme(VS_SAMPLE, "Noir"));
    assert_eq!(t.backups("Code/User"), 1);

    // undo: the user's file exactly as it was
    act(&t.dir, &env, "vscode", "undo").unwrap();
    assert_eq!(t.read("Code/User/settings.json"), VS_SAMPLE);
    assert_eq!(state(&t, &env, "vscode")["state"], "available");
    publish(&t.file("pistachio/shared-theme"), "pistachio", &env).unwrap();
    assert_eq!(t.read("Code/User/settings.json"), VS_SAMPLE, "no line of ours: a Colours switch leaves it");

    // a theme of the user's own: asked first, then replaced and given back
    let own = VS_SAMPLE.replacen("{\n", "{\n    \"workbench.colorTheme\": \"Default Dark Modern\",\n", 1);
    t.put("Code/User/settings.json", &own);
    assert_eq!(state(&t, &env, "vscode")["state"], "own");
    act(&t.dir, &env, "vscode", "setup").unwrap();
    assert_eq!(t.read("Code/User/settings.json"), own, "setup leaves an own theme alone");
    t.put("pistachio/shared-theme", "noir\n");
    assert_eq!(act(&t.dir, &env, "vscode", "use").unwrap()["state"], "following");
    assert!(t.read("Code/User/settings.json").contains("\"Noir\" /* pistachio-shell theming (was \"Default Dark Modern\") */"), "use follows the current Colours");
    act(&t.dir, &env, "vscode", "undo").unwrap();
    assert_eq!(t.read("Code/User/settings.json"), own);

    // ours, picked by hand: quietly wired, and undo keeps that pick
    let picked = VS_SAMPLE.replacen("{\n", "{\n    \"workbench.colorTheme\": \"Pistachio Noir\",\n", 1);
    t.put("Code/User/settings.json", &picked);
    assert_eq!(state(&t, &env, "vscode")["state"], "available");
    act(&t.dir, &env, "vscode", "setup").unwrap();
    assert_eq!(state(&t, &env, "vscode")["state"], "following");
    act(&t.dir, &env, "vscode", "undo").unwrap();
    assert_eq!(t.read("Code/User/settings.json").replace("\"Noir\"", "\"Pistachio Noir\""), picked);

    // no settings.json yet (installed, never opened)
    std::fs::remove_file(t.file("Code/User/settings.json")).unwrap();
    act(&t.dir, &env, "vscode", "setup").unwrap();
    assert!(jsonc_ok(&t.read("Code/User/settings.json")) && state(&t, &env, "vscode")["state"] == "following");
}

#[test]
fn vscode_refusals() {
    let t = T::new("vscode-no", &[]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    fake_code(&t, true);
    t.put("Code/User/settings.json", VS_SAMPLE);
    let s = act(&t.dir, &env, "vscode", "setup").unwrap();
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("disk full"), "install failure says why: {s}");
    assert_eq!(t.read("Code/User/settings.json"), VS_SAMPLE, "and nothing was written");

    fake_code(&t, false);
    t.put("Code/User/settings.json", &VS_SAMPLE.replacen("{\n", "{\n    \"window.autoDetectColorScheme\": true,\n", 1));
    let s = state(&t, &env, "vscode");
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("autoDetectColorScheme"), "{s}");

    // the user saves while psc writes
    t.put("Code/User/settings.json", VS_SAMPLE);
    let settings = t.file("Code/User/settings.json");
    BEFORE_WRITE.with(|h| *h.borrow_mut() = Some(Box::new(move || {
        let text = std::fs::read_to_string(&settings).unwrap();
        std::fs::write(&settings, text.replace("true,", "false,")).unwrap();
    })));
    let s = act(&t.dir, &env, "vscode", "setup").unwrap();
    BEFORE_WRITE.with(|h| *h.borrow_mut() = None);
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("changed"), "{s}");
    assert!(!t.read("Code/User/settings.json").contains("pistachio-shell"));

    // a dotfile manager's link
    std::fs::remove_file(t.file("Code/User/settings.json")).unwrap();
    t.put("dotfiles/settings.json", VS_SAMPLE);
    std::os::unix::fs::symlink(t.file("dotfiles/settings.json"), t.file("Code/User/settings.json")).unwrap();
    let s = state(&t, &env, "vscode");
    assert!(s["state"] == "unsupported" && s["detail"].as_str().unwrap().contains("link"), "{s}");
}

// OLED black (owner, 22 November 2026: "integrate oled also inside themes integrations"): Noir in
// shared-theme for FM and Text (they read exactly "noir"), and a marker beside it for the apps that know OLED
#[test]
fn oled_publication() {
    let t = T::new("oled", &[]);
    let reloads = Cell::new(0);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|app| if app == "kitty" { reloads.set(reloads.get() + 1) } };
    let path = t.file("pistachio/shared-theme");
    t.put("kitty/pistachio-shared.conf", "include noir.conf\n");
    publish(&path, "oled", &env).unwrap();
    assert_eq!(t.read("pistachio/shared-theme"), "noir\n", "FM and Text keep reading plain Noir");
    assert_eq!(t.read("pistachio/shared-oled"), "on\n");
    assert_eq!(current_scheme(&t.dir), "oled");
    assert_eq!(t.read("kitty/pistachio-shared.conf"), kitty_scheme("oled"));
    assert!(kitty_scheme("oled").contains("background              #000000"), "{}", kitty_scheme("oled"));
    assert_eq!(reloads.get(), 1);
    publish(&path, "noir", &env).unwrap();
    assert!(!t.file("pistachio/shared-oled").exists(), "plain Noir drops the marker");
    assert_eq!(current_scheme(&t.dir), "noir");
    assert_eq!(t.read("kitty/pistachio-shared.conf"), kitty_scheme("noir"));
    // a marker left beside Pistachio Noir means nothing
    t.put("pistachio/shared-oled", "on\n");
    publish(&path, "pistachio", &env).unwrap();
    assert!(!t.file("pistachio/shared-oled").exists());
    t.put("pistachio/shared-oled", "on\n");
    assert_eq!(current_scheme(&t.dir), "pistachio");
    assert_eq!(vs_theme("oled"), "OLED Noir");
    assert!(VS_FILES.iter().any(|(name, _)| *name == "themes/oled-noir.json"));
    let package: Value = serde_json::from_slice(VS_PACKAGE).unwrap();
    assert!(package["contributes"]["themes"].as_array().unwrap().iter().any(|t| t["label"] == "OLED Noir" && t["path"] == "./themes/oled-noir.json"));
}

#[test]
fn oled_vscode_and_kitty_setup() {
    let t = T::new("oledapps", &["kitty"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    fake_code(&t, false);
    t.put("Code/User/settings.json", VS_SAMPLE);
    t.put("pistachio/shared-theme", "noir\n");
    t.put("pistachio/shared-oled", "on\n");
    act(&t.dir, &env, "vscode", "setup").unwrap();
    assert_eq!(t.read("Code/User/settings.json"), vs_with_theme(VS_SAMPLE, "OLED Noir"), "setup follows OLED");
    act(&t.dir, &env, "kitty", "setup").unwrap();
    assert_eq!(t.read("kitty/pistachio-shared.conf"), kitty_scheme("oled"));
    assert!(t.file("kitty/oled-noir.conf").exists());
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(t.read("Code/User/settings.json"), vs_with_theme(VS_SAMPLE, "Noir"));
    // OLED Noir picked by hand counts as ours
    let picked = VS_SAMPLE.replacen("{\n", "{\n    \"workbench.colorTheme\": \"OLED Noir\",\n", 1);
    t.put("Code/User/settings.json", &picked);
    assert_eq!(state(&t, &env, "vscode")["state"], "available");
}

#[test]
fn kitty_itself_reads_the_setup_as_oled() {
    let Some(kitty) = std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).map(|d| d.join("kitty")).find(|p| p.is_file()) else {
        return;
    };
    let t = T::new("kittyoled", &["kitty"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    t.put("kitty/kitty.conf", "include pistachio-noir.conf\n");
    t.put("pistachio/shared-theme", "noir\n");
    t.put("pistachio/shared-oled", "on\n");
    act(&t.dir, &env, "kitty", "setup");
    let probe = format!("from kitty.config import load_config; b=[]; o=load_config({:?}, accumulate_bad_lines=b); print(o.background, [str(x.exception) for x in b])", t.file("kitty/kitty.conf"));
    let out = std::process::Command::new(kitty).args(["+runpy", &probe]).output().unwrap();
    let all = String::from_utf8_lossy(&out.stdout).to_string() + &String::from_utf8_lossy(&out.stderr);
    assert!(all.contains("Color(0, 0, 0) []"), "OLED Noir, and no bad lines: {all}");
}

// a Neovim set up by an older psc has colour files without OLED Noir: a switch brings them up to date
#[test]
fn publish_refreshes_a_following_neovim() {
    let t = T::new("nvimfresh", &["nvim"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    t.put("nvim/init.lua", "vim.opt.number = true\n");
    act(&t.dir, &env, "neovim", "setup").unwrap();
    t.put("nvim/colors/pistachio-noir.lua", "-- older colours\n");
    t.put("nvim/lua/pistachio-shared.lua", "-- older reader\n");
    publish(&t.file("pistachio/shared-theme"), "oled", &env).unwrap();
    assert_eq!(std::fs::read(t.file("nvim/colors/pistachio-noir.lua")).unwrap(), NVIM_COLORS);
    assert_eq!(std::fs::read(t.file("nvim/lua/pistachio-shared.lua")).unwrap(), NVIM_SHARED);
    assert_eq!(t.backups("nvim/colors") + t.backups("nvim/lua"), 2, "the older files are kept");
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(t.backups("nvim/colors") + t.backups("nvim/lua"), 2, "nothing to do when they match");
    // not set up: left alone
    let u = T::new("nvimalone", &["nvim"]);
    u.put("nvim/init.lua", "vim.opt.number = true\n");
    publish(&u.file("pistachio/shared-theme"), "oled", &env).unwrap();
    assert!(!u.file("nvim/colors/pistachio-noir.lua").exists());
}

// a newer psc with a new theme (OLED Noir): a switch reinstalls an out-of-date extension before naming it
#[test]
fn publish_reinstalls_an_old_vscode_extension() {
    let t = T::new("vsfresh", &[]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    fake_code(&t, false);
    t.put("Code/User/settings.json", VS_SAMPLE);
    t.put("pistachio/shared-theme", "noir\n");
    act(&t.dir, &env, "vscode", "setup").unwrap();
    installed_by_code(&t);
    std::fs::remove_file(t.home().join(".vscode/extensions/pistachio-shell.pistachio-noir-1.0.0/themes/oled-noir.json")).unwrap();
    let installs = || std::fs::read_to_string(t.bin.join("code.log")).unwrap_or_default().lines().count();
    assert_eq!(installs(), 1);
    publish(&t.file("pistachio/shared-theme"), "oled", &env).unwrap();
    assert_eq!(installs(), 2, "installed again");
    assert_eq!(t.read("Code/User/settings.json"), vs_with_theme(VS_SAMPLE, "OLED Noir"));
    installed_by_code(&t);
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(installs(), 2, "up to date: no install");
}

// --- the apps of 28 November 2026 (theme/extra.rs) ------------------------------------------------

use std::os::unix::fs::MetadataExt;

fn counted<'a>(seen: &'a std::cell::RefCell<Vec<String>>) -> impl Fn(&str) + 'a {
    move |app: &str| seen.borrow_mut().push(app.to_string())
}

#[test]
fn new_apps_missing_then_available() {
    let t = T::new("extra-missing", &["btop", "yazi", "zathura", "vesktop"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    std::fs::create_dir_all(&t.dir).unwrap();
    for app in ["gtk", "vesktop", "btop", "yazi", "zathura"] {
        assert_eq!(state(&t, &env, app)["state"], "available", "{app}");
    }
}

/// A stand-in gsettings: `get` prints the saved theme, `set` saves it and every call is logged.
fn fake_gsettings(t: &T, theme: &str) {
    let state = t.dir.parent().unwrap().join("gtk-theme");
    std::fs::write(&state, format!("'{theme}'\n")).unwrap();
    let script = format!("#!/bin/sh\necho \"$@\" >> {0}.log\nif [ \"$1\" = get ]; then read -r l < {0}; echo \"$l\"; else printf \"'%s'\\n\" \"$4\" > {0}; fi\n", state.display());
    std::fs::write(t.bin.join("gsettings"), script).unwrap();
    std::fs::set_permissions(t.bin.join("gsettings"), std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
}
fn gtk_theme(t: &T) -> String {
    std::fs::read_to_string(t.dir.parent().unwrap().join("gtk-theme")).unwrap().trim().trim_matches('\'').to_string()
}

#[test]
fn gtk_follows_and_undoes() {
    let t = T::new("extra-gtk", &[]);
    fake_gsettings(&t, "Adwaita");
    std::fs::create_dir_all(t.home().join(".local/share/themes/adw-gtk3-dark/gtk-3.0")).unwrap();
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    // a gtk.css with rules of the user's own, no colours: the import goes first, the rules stay
    t.put("gtk-4.0/gtk.css", "window { margin: 1px; }\n");
    assert_eq!(state(&t, &env, "gtk")["state"], "available");
    t.put("pistachio/shared-theme", "noir\n");
    assert_eq!(act(&t.dir, &env, "gtk", "setup").unwrap()["state"], "following");
    let css = t.read("gtk-4.0/gtk.css");
    assert!(css.starts_with("/* pistachio-shell theming") && css.contains("@import url(\"pistachio-shared.css\");\nwindow { margin: 1px; }\n"), "{css}");
    assert_eq!(t.read("gtk-4.0/pistachio-shared.css"), extra_file("gtk/gtk4-noir.css"));
    assert_eq!(t.read("gtk-3.0/pistachio-shared.css"), extra_file("gtk/gtk3-noir.css"));
    assert!(t.read("gtk-3.0/gtk.css").contains("(gtk-theme was \"Adwaita\")"), "{}", t.read("gtk-3.0/gtk.css"));
    assert_eq!(gtk_theme(&t), "adw-gtk3-dark");
    // a switch rewrites both colour files
    publish(&t.file("pistachio/shared-theme"), "oled", &env).unwrap();
    assert_eq!(t.read("gtk-4.0/pistachio-shared.css"), extra_file("gtk/gtk4-oled-noir.css"));
    assert_eq!(t.read("gtk-3.0/pistachio-shared.css"), extra_file("gtk/gtk3-oled-noir.css"));
    // undo: the user's file as it was, the shell's files gone, GTK 3's theme back
    act(&t.dir, &env, "gtk", "undo").unwrap();
    assert_eq!(t.read("gtk-4.0/gtk.css"), "window { margin: 1px; }\n");
    assert!(!t.file("gtk-3.0/gtk.css").exists() && !t.file("gtk-4.0/pistachio-shared.css").exists() && !t.file("gtk-3.0/pistachio-shared.css").exists());
    assert_eq!(gtk_theme(&t), "Adwaita");
    assert_eq!(state(&t, &env, "gtk")["state"], "available");
}

#[test]
fn gtk_own_colours_are_asked_about_and_come_back() {
    let t = T::new("extra-gtk-own", &[]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    let mine = "/* mine */\n@define-color accent_bg_color #FF0000;\n:root { --window-bg-color: #101010; }\n";
    t.put("gtk-4.0/gtk.css", mine);
    assert_eq!(state(&t, &env, "gtk")["state"], "own");
    act(&t.dir, &env, "gtk", "setup").unwrap();
    assert_eq!(t.read("gtk-4.0/gtk.css"), mine, "a quiet setup leaves an own theme alone");
    assert_eq!(act(&t.dir, &env, "gtk", "use").unwrap()["state"], "following");
    assert_eq!(t.read("gtk-4.0/gtk.css.pistachio-own"), mine);
    assert!(!t.read("gtk-4.0/gtk.css").contains("#FF0000"));
    assert_eq!(t.backups("gtk-4.0"), 1);
    // the user adds a rule after the shell's lines, then switches off: their file, then that rule
    let now = t.read("gtk-4.0/gtk.css");
    t.put("gtk-4.0/gtk.css", &(now + "label { font-weight: 700; }\n"));
    act(&t.dir, &env, "gtk", "undo").unwrap();
    assert_eq!(t.read("gtk-4.0/gtk.css"), format!("{mine}label {{ font-weight: 700; }}\n"));
    assert!(!t.file("gtk-4.0/gtk.css.pistachio-own").exists());
    // a theme picked in gsettings is the user's own too
    let t = T::new("extra-gtk-theme", &[]);
    fake_gsettings(&t, "Catppuccin-Mocha");
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    std::fs::create_dir_all(&t.dir).unwrap();
    assert_eq!(state(&t, &env, "gtk")["state"], "own");
}

fn extra_file(p: &str) -> String {
    std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../integrations").join(p)).unwrap()
}

#[test]
fn btop_follows_switches_live_and_undoes() {
    let t = T::new("extra-btop", &["btop"]);
    let seen = std::cell::RefCell::new(vec![]);
    let reload = counted(&seen);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &reload };
    let conf = "#? Config file for btop\ncolor_theme = \"Default\"\ntheme_background = true\n";
    t.put("btop/btop.conf", conf);
    assert_eq!(state(&t, &env, "btop")["state"], "available");
    assert_eq!(act(&t.dir, &env, "btop", "setup").unwrap()["state"], "following");
    assert_eq!(t.read("btop/btop.conf"), conf.replace("\"Default\"", "\"pistachio-shell\""));
    let theme = t.read("btop/themes/pistachio-shell.theme");
    assert!(theme.ends_with(&extra_file("btop/pistachio-noir.theme")) && theme.lines().next().unwrap().contains("color_theme was \"Default\""), "{theme}");
    assert_eq!(*seen.borrow(), ["btop"], "a running btop reads its config again (SIGUSR2)");
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert!(t.read("btop/themes/pistachio-shell.theme").ends_with(&extra_file("btop/noir.theme")));
    assert_eq!(seen.borrow().iter().filter(|a| *a == "btop").count(), 2);
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(seen.borrow().iter().filter(|a| *a == "btop").count(), 2, "no reload when nothing changed");
    act(&t.dir, &env, "btop", "undo").unwrap();
    assert_eq!(t.read("btop/btop.conf"), conf);
    assert!(!t.file("btop/themes/pistachio-shell.theme").exists());
    // an own theme: asked first, and back after undo
    let own = conf.replace("Default", "dracula");
    t.put("btop/btop.conf", &own);
    assert_eq!(state(&t, &env, "btop")["state"], "own");
    act(&t.dir, &env, "btop", "use").unwrap();
    assert!(t.read("btop/btop.conf").contains("color_theme = \"pistachio-shell\""));
    act(&t.dir, &env, "btop", "undo").unwrap();
    assert_eq!(t.read("btop/btop.conf"), own);
}

#[test]
fn yazi_follows_and_puts_an_own_theme_back() {
    let t = T::new("extra-yazi", &["yazi"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    std::fs::create_dir_all(&t.dir).unwrap();
    assert_eq!(act(&t.dir, &env, "yazi", "setup").unwrap()["state"], "following");
    assert!(t.read("yazi/theme.toml").contains("[flavor]\ndark = \"pistachio-shell\"\nlight = \"pistachio-shell\"\n"));
    assert_eq!(t.read("yazi/flavors/pistachio-shell.yazi/flavor.toml"), extra_file("yazi/pistachio-noir.toml"));
    assert_eq!(t.read("yazi/flavors/pistachio-shell.yazi/tmtheme.xml"), extra_file("yazi/pistachio-noir.tmtheme.xml"));
    publish(&t.file("pistachio/shared-theme"), "oled", &env).unwrap();
    assert_eq!(t.read("yazi/flavors/pistachio-shell.yazi/flavor.toml"), extra_file("yazi/oled-noir.toml"));
    act(&t.dir, &env, "yazi", "undo").unwrap();
    assert!(!t.file("yazi/theme.toml").exists() && !t.file("yazi/flavors/pistachio-shell.yazi").exists());
    let mine = "[mgr]\ncwd = { fg = \"red\" }\n";
    t.put("yazi/theme.toml", mine);
    assert_eq!(state(&t, &env, "yazi")["state"], "own");
    act(&t.dir, &env, "yazi", "use").unwrap();
    assert_eq!(state(&t, &env, "yazi")["state"], "following");
    act(&t.dir, &env, "yazi", "undo").unwrap();
    assert_eq!(t.read("yazi/theme.toml"), mine);
    assert!(!t.file("yazi/theme.toml.pistachio-own").exists());
}

#[test]
fn zathura_follows_reloads_and_undoes() {
    let t = T::new("extra-zathura", &["zathura"]);
    let seen = std::cell::RefCell::new(vec![]);
    let reload = counted(&seen);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &reload };
    t.put("zathura/zathurarc", "set recolor true\nset recolor-keephue true\n");
    assert_eq!(state(&t, &env, "zathura")["state"], "available", "a switch isn't a colour");
    let mine = "set selection-clipboard clipboard\nset default-bg \"#000000\"\n";
    t.put("zathura/zathurarc", mine);
    assert_eq!(state(&t, &env, "zathura")["state"], "own");
    act(&t.dir, &env, "zathura", "use").unwrap();
    assert!(t.read("zathura/zathurarc").starts_with(mine) && t.read("zathura/zathurarc").ends_with("\ninclude pistachio-shared\n"), "comes last, so it wins");
    assert_eq!(t.read("zathura/pistachio-shared"), extra_file("zathura/pistachio-noir"));
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(t.read("zathura/pistachio-shared"), extra_file("zathura/noir"));
    assert_eq!(seen.borrow().iter().filter(|a| *a == "zathura").count(), 2, "open windows read their config again");
    act(&t.dir, &env, "zathura", "undo").unwrap();
    assert_eq!(t.read("zathura/zathurarc"), mine);
    assert!(!t.file("zathura/pistachio-shared").exists());
}

#[test]
fn vesktop_block_is_written_in_place() {
    let t = T::new("extra-vesktop", &["vesktop"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    let mine = ".mine { color: red; }\n";
    t.put("vesktop/settings/quickCss.css", mine);
    t.put("vesktop/settings/settings.json", "{\"useQuickCss\": true, \"enabledThemes\": []}");
    let inode = || std::fs::metadata(t.file("vesktop/settings/quickCss.css")).unwrap().ino();
    let first = inode();
    assert_eq!(act(&t.dir, &env, "vesktop", "setup").unwrap()["state"], "following");
    let css = t.read("vesktop/settings/quickCss.css");
    assert!(css.starts_with(mine) && css.contains(extra_file("vesktop/pistachio-noir.css").trim()), "{css}");
    assert_eq!(t.backups("vesktop/settings"), 1, "setup backs it up");
    publish(&t.file("pistachio/shared-theme"), "noir", &env).unwrap();
    assert_eq!(t.backups("vesktop/settings"), 1, "a colour switch makes no new backup");
    let css = t.read("vesktop/settings/quickCss.css");
    assert!(css.starts_with(mine) && css.contains(extra_file("vesktop/noir.css").trim()) && css.matches("theming: start").count() == 1, "{css}");
    assert_eq!(inode(), first, "Vencord's file watch stays on the same file");
    act(&t.dir, &env, "vesktop", "undo").unwrap();
    assert_eq!(t.read("vesktop/settings/quickCss.css"), mine);
    assert_eq!(inode(), first);
    // a Vencord theme of the user's own is asked about; QuickCSS off is said
    t.put("vesktop/settings/settings.json", "{\"useQuickCss\": false, \"enabledThemes\": [\"midnight.theme.css\"]}");
    assert_eq!(state(&t, &env, "vesktop")["state"], "own");
    act(&t.dir, &env, "vesktop", "use").unwrap();
    let s = state(&t, &env, "vesktop");
    assert!(s["state"] == "following" && s["detail"].as_str().unwrap().contains("QuickCSS"), "{s}");
}

#[test]
fn new_apps_symlinked_configs_are_left_alone() {
    let t = T::new("extra-links", &["btop", "yazi", "zathura", "vesktop"]);
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|_| {} };
    t.put("dotfiles/x", "x\n");
    for (app, file) in [("gtk", "gtk-4.0/gtk.css"), ("btop", "btop/btop.conf"), ("yazi", "yazi/theme.toml"), ("zathura", "zathura/zathurarc"), ("vesktop", "vesktop/settings/quickCss.css")] {
        std::fs::create_dir_all(t.file(file).parent().unwrap()).unwrap();
        std::os::unix::fs::symlink(t.file("dotfiles/x"), t.file(file)).unwrap();
        assert_eq!(act(&t.dir, &env, app, "use").unwrap()["state"], "unsupported", "{app}");
        assert_eq!(t.read("dotfiles/x"), "x\n", "{app}");
    }
}

#[test]
fn each_vsix_gets_its_own_file() {
    // the name had only the pid and the second: VS Code tests running side by side in one process
    // removed each other's file (28 November 2026)
    assert_ne!(vsix_temp(), vsix_temp());
}

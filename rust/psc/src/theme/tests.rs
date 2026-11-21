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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| reloads.set(reloads.get() + 1) };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
    std::fs::create_dir_all(&t.dir).unwrap();
    let states: Vec<_> = status(&t.dir, &env).iter().map(|a| a["state"].as_str().unwrap().to_string()).collect();
    assert_eq!(states, ["missing", "missing", "missing"], "kitty, neovim, vscode");
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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
    assert_eq!(v["apps"].as_array().unwrap().len(), 3);
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
    assert_eq!(state(&t, &env, "vscode")["state"], "missing");
    fake_code(&t, false);
    assert_eq!(state(&t, &env, "vscode")["state"], "available", "the code command alone");
    t.put("Code/User/settings.json", VS_SAMPLE);
    let s = act(&t.dir, &env, "vscode", "setup").unwrap();
    let log = std::fs::read_to_string(t.bin.join("code.log")).unwrap_or_else(|_| panic!("code not run: {s}"));
    assert!(log.starts_with("--install-extension ") && log.trim_end().ends_with(".vsix --force"), "{log}");
    let vsix = std::fs::read(t.bin.join("got.vsix")).unwrap();
    assert_eq!(&vsix[..4], b"PK\x03\x04");
    assert!(!std::fs::read_dir(std::env::temp_dir()).unwrap().any(|e| e.unwrap().file_name().to_string_lossy().starts_with(&format!("pistachio-noir-{}-", std::process::id()))), "the .vsix is removed");
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
    let env = Env { path: t.bin.clone().into(), home: t.home(), reload: &|| {} };
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

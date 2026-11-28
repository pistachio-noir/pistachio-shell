"""The app themes of 28 November 2026 (GTK 3/4, yazi; btop, zathura and Vesktop by cargo test), read by
the apps themselves: `psc theme setup` in a throwaway config folder, then GTK 4's and GTK 3's own CSS
parser on the gtk.css it wrote (a little C program built with pkg-config), and yazi itself in a pseudo
terminal, for each of the three schemes. Also: the theme files are up to date with src/Theme.qml.

psc runs with a PATH of stand-ins only (no pkill) and no session bus, so it can't reach running apps;
nothing of the owner's is read or changed. PSC= another psc build (default: rust/target/release/psc)."""
import os, pathlib, pty, re, select, shutil, struct, subprocess, sys, tempfile, time, fcntl, termios

ROOT = pathlib.Path(__file__).resolve().parents[1]
PSC = os.environ.get("PSC", str(ROOT / "rust/target/release/psc"))
SCHEMES = {"pistachio": ("pistachio-noir", "#15170F"), "noir": ("noir", "#111111"), "oled": ("oled-noir", "#000000")}

CHECKER = r'''
#include <gtk/gtk.h>
static int errors = 0;
static void on_error(GtkCssProvider *p, GtkCssSection *s, const GError *e, gpointer d) {
  g_printerr("ERROR line %u: %s\n", (unsigned) gtk_css_section_get_start_location(s)->lines + 1, e->message); errors++; }
int main(int argc, char **argv) {
  gtk_init();
  GtkCssProvider *p = gtk_css_provider_new();
  g_signal_connect(p, "parsing-error", G_CALLBACK(on_error), NULL);
  gtk_css_provider_load_from_path(p, argv[1]);
  char *text = gtk_css_provider_to_string(p); g_print("%s", text); g_free(text);
  return errors ? 1 : 0;
}
'''


def ok(text):
    print("ok:", text)


def check_files():
    out = subprocess.run([sys.executable, "-B", str(ROOT / "tools/make-app-themes.py"), "--check"], capture_output=True, text=True)
    assert out.returncode == 0, out.stdout + out.stderr
    ok("the theme files match src/Theme.qml")


def build_checkers(work):
    """GTK 4's and GTK 3's own CSS parsers, or None where gcc or the headers are missing."""
    built = {}
    for name, pkg, src in (("gtk4", "gtk4", CHECKER),
                           ("gtk3", "gtk+-3.0", CHECKER.replace("gtk_init();", "gtk_init(&argc, &argv);")
                            .replace("gtk_css_provider_load_from_path(p, argv[1]);", "gtk_css_provider_load_from_path(p, argv[1], NULL);")
                            .replace("gtk_css_section_get_start_location(s)->lines", "gtk_css_section_get_start_line(s)"))):
        if not shutil.which("gcc") or subprocess.run(["pkg-config", "--exists", pkg]).returncode != 0:
            continue
        c = work / f"{name}.c"; c.write_text(src)
        flags = subprocess.run(["pkg-config", "--cflags", "--libs", pkg], capture_output=True, text=True, check=True).stdout.split()
        subprocess.run(["gcc", str(c), "-o", str(work / name)] + flags, check=True)
        built[name] = work / name
    return built


def yazi_draws(yazi, config, home):
    """yazi's screen for a second (it waits for the terminal's answers to its queries first)."""
    env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / "state"), YAZI_CONFIG_HOME=str(config), TERM="xterm-256color")
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(yazi, [yazi, str(home)], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    out, answered, start = b"", False, time.time()
    while time.time() - start < 4:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            out += chunk
            if not answered and b"\x1b[0c" in out:
                os.write(fd, b"\x1b]11;rgb:0000/0000/0000\x1b\\\x1b[?62;22c"); answered = True
        if answered and time.time() - start > 2.5:
            break
    os.kill(pid, 9); os.waitpid(pid, 0)
    return out.decode("utf-8", "replace")


def main():
    check_files()
    assert pathlib.Path(PSC).exists(), f"no psc at {PSC}: cd rust && cargo build --release -p psc"
    with tempfile.TemporaryDirectory(prefix="pistachio-app-themes-") as d:
        base = pathlib.Path(d)
        home, config, bin_ = base / "home", base / "config", base / "bin"
        for p in (home, config / "yazi", bin_):
            p.mkdir(parents=True)
        (home / "a.txt").write_text("a\n"); (home / "folder").mkdir()
        # gsettings: GTK 3's theme, kept in a file
        (bin_ / "gsettings").write_text(f"#!/bin/sh\nif [ \"$1\" = get ]; then read -r l < {base}/gtk-theme; echo \"$l\"; else echo \"'$4'\" > {base}/gtk-theme; fi\n")
        (bin_ / "gsettings").chmod(0o755)
        (base / "gtk-theme").write_text("'Adwaita'\n")
        (home / ".local/share/themes/adw-gtk3-dark/gtk-3.0").mkdir(parents=True)
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), PATH=str(bin_),
                   DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(base / "no-bus"))
        psc = lambda *a: subprocess.run([PSC, "theme", *a], env=env, capture_output=True, text=True, timeout=30)
        for app in ("gtk", "yazi"):
            out = psc("setup", app)
            assert f'"id":"{app}","name"' in out.stdout and '"state":"following"' in out.stdout.split(f'"id":"{app}"')[1].split("}")[0], out.stdout + out.stderr
        assert (base / "gtk-theme").read_text().strip() == "'adw-gtk3-dark'", "GTK 3 apps get adw-gtk3"
        ok("psc sets up GTK and yazi")
        checkers = build_checkers(base) if os.environ.get("WAYLAND_DISPLAY") else {}
        yazi = shutil.which("yazi")
        for scheme, (name, bg) in SCHEMES.items():
            out = psc("publish", scheme)
            assert out.returncode == 0, out.stdout + out.stderr
            for version, checker in checkers.items():
                folder = config / ("gtk-4.0" if version == "gtk4" else "gtk-3.0")
                read = subprocess.run([str(checker), str(folder / "gtk.css")], capture_output=True, text=True, timeout=30)
                assert read.returncode == 0, read.stderr
                # the @import was found and read: its colours are in what GTK parsed
                rgb = "rgb({},{},{})".format(*(int(bg[i:i + 2], 16) for i in (1, 3, 5)))
                assert bg.lower() in read.stdout.lower() or rgb in read.stdout.replace(" ", ""), f"{version} {scheme}: no {bg} in\n{read.stdout[:400]}"
            if yazi:
                screen = yazi_draws(yazi, config / "yazi", home)
                assert "load failed" not in screen, screen[-800:]
                pistachio = {"pistachio": "159;216;138", "noir": "189;189;189", "oled": "150;150;150"}[scheme]
                assert pistachio in screen, f"yazi {scheme}: the hovered row isn't the shell's active colour"
        ok("GTK 4 and GTK 3 read gtk.css and its colours in all three schemes" if checkers else "skipped GTK's own parser (needs gcc, pkg-config, GTK headers and a Wayland session)")
        ok("yazi draws with the flavor in all three schemes" if yazi else "skipped yazi itself (not installed)")
        out = psc("undo", "gtk"); out2 = psc("undo", "yazi")
        assert not (config / "gtk-4.0/gtk.css").exists() and not (config / "yazi/theme.toml").exists(), out.stdout + out2.stdout
        assert (base / "gtk-theme").read_text().strip() == "'Adwaita'"
        ok("undo removes it all and gives GTK 3 its theme back")


main()

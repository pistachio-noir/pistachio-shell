//! `psc ipc`: every target and its functions, from `qs ipc show`.
pub fn parse(show: &str) -> Vec<(String, Vec<String>)> {
    let mut out: Vec<(String, Vec<String>)> = vec![];
    for line in show.lines() {
        if let Some(t) = line.strip_prefix("target ") {
            out.push((t.trim().to_string(), vec![]));
        } else if let (Some(f), Some(last)) = (line.trim().strip_prefix("function "), out.last_mut()) {
            last.1.push(f.to_string());
        }
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

/// `set(path: string): void` → ("set", "path: string", "") ; `status(): string` → ("status", "", "string")
fn split(signature: &str) -> (&str, &str, &str) {
    let (name, rest) = signature.split_once('(').unwrap_or((signature, ")"));
    let (args, ret) = rest.rsplit_once(')').unwrap_or((rest, ""));
    let ret = ret.trim_start_matches(':').trim();
    (name, args.trim(), if ret == "void" { "" } else { ret })
}

/// The list, functions lined up in one column; colour (pistachio targets, bold names, dim
/// arguments) only when `colour` is set, i.e. on a terminal without NO_COLOR.
pub fn text(targets: &[(String, Vec<String>)], colour: bool) -> String {
    let paint = |code: &str, text: &str| if colour { format!("\x1b[{code}m{text}\x1b[0m") } else { text.to_string() };
    let width = targets.iter().flat_map(|(_, fs)| fs.iter().map(|f| split(f).0.chars().count())).max().unwrap_or(0) + 3;
    let mut out = paint("2", "Call one with: psc <target> <function> [arguments]") + "\n";
    for (target, functions) in targets {
        out += &format!("\n{}\n", paint("1;38;2;159;216;138", target));
        for f in functions {
            let (name, args, ret) = split(f);
            let detail = match (args.is_empty(), ret.is_empty()) {
                (true, true) => String::new(),
                (false, true) => args.to_string(),
                (true, false) => format!("→ {ret}"),
                (false, false) => format!("{args} → {ret}"),
            };
            if detail.is_empty() {
                out += &format!("  {}\n", paint("1", name));
            } else {
                let pad = " ".repeat(width - name.chars().count());
                out += &format!("  {}{pad}{}\n", paint("1", name), paint("2", &detail));
            }
        }
    }
    out
}

/// Colour only on a terminal, and never with NO_COLOR set (no-color.org).
pub fn colour_wanted() -> bool {
    std::env::var_os("NO_COLOR").is_none_or(|v| v.is_empty()) && unsafe { libc::isatty(1) } == 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ipc_parse() {
        let live = "target quicksettings\n  function mixer(): void\n  function toggle(): void\n\
                    target notifications\n  function toggleDnd(): void\ntarget wallpaper\n  function set(path: string): void\n";
        assert_eq!(parse(live), vec![
            ("notifications".into(), vec!["toggleDnd(): void".into()]),
            ("quicksettings".into(), vec!["mixer(): void".into(), "toggle(): void".into()]),
            ("wallpaper".into(), vec!["set(path: string): void".into()])]);
        assert!(parse("").is_empty());
    }

    #[test]
    fn ipc_text_plain() {
        let targets = parse("target wallpaper\n  function set(path: string): void\n  function random(): void\n\
                             target settings\n  function status(): string\n");
        assert_eq!(text(&targets, false),
            "Call one with: psc <target> <function> [arguments]\n\n\
             settings\n  status   → string\n\n\
             wallpaper\n  set      path: string\n  random\n");
    }
}

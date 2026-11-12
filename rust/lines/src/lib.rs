//! JSON lines between the shell and a helper: events go out on stdout, the shell's answers come in
//! on stdin. A helper ends when its stdin closes, so it never outlives the shell.

use std::io::{self, BufRead, Read, Write};

/// A longer line is dropped: nothing the shell sends comes near it.
pub const MAX_LINE: usize = 1 << 20;

/// Writes one event line to stdout. The shell reading it is gone when the write fails, so the
/// helper leaves quietly.
pub fn emit(value: &serde_json::Value) {
    let mut out = io::stdout().lock();
    if write_line(&mut out, value).is_err() {
        std::process::exit(0);
    }
}

/// One `\n`-ended JSON line, flushed.
pub fn write_line(out: &mut impl Write, value: &serde_json::Value) -> io::Result<()> {
    let mut line = serde_json::to_vec(value)?;
    line.push(b'\n');
    out.write_all(&line)?;
    out.flush()
}

/// A line for the shell's log (it prints a helper's stderr as warnings).
pub fn log(text: &str) {
    let _ = writeln!(io::stderr().lock(), "{text}");
}

/// Calls `on_line` for each line on stdin until it closes.
pub fn read_lines(on_line: impl FnMut(&str)) {
    read_lines_from(io::stdin().lock(), on_line);
}

/// Calls `on_line` for each line of `input` that isn't blank, until its end. Lines over
/// [`MAX_LINE`] and lines that aren't UTF-8 are logged and skipped.
pub fn read_lines_from(input: impl Read, mut on_line: impl FnMut(&str)) {
    let mut input = io::BufReader::new(input);
    let mut line = Vec::new();
    loop {
        line.fill(0); // what the last line held (a password, perhaps) doesn't stay behind
        line.clear();
        // one byte over the limit shows the line is too long without reading all of it into memory
        match (&mut input).take(MAX_LINE as u64 + 1).read_until(b'\n', &mut line) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        if line.len() > MAX_LINE && line.last() != Some(&b'\n') {
            log("ignored answer: line too long");
            if !skip_rest_of_line(&mut input) {
                return;
            }
            continue;
        }
        match std::str::from_utf8(&line) {
            Ok(text) if !text.trim().is_empty() => on_line(text.trim_end_matches(['\n', '\r'])),
            Ok(_) => {}
            Err(_) => log("ignored answer: not text"),
        }
    }
}

/// Reads up to and including the next newline; false at the end of the input.
fn skip_rest_of_line(input: &mut impl BufRead) -> bool {
    loop {
        let (used, found) = match input.fill_buf() {
            Ok([]) | Err(_) => return false,
            Ok(buffer) => match buffer.iter().position(|b| *b == b'\n') {
                Some(at) => (at + 1, true),
                None => (buffer.len(), false),
            },
        };
        input.consume(used);
        if found {
            return true;
        }
    }
}

/// Asks the kernel to end this process when the shell that started it dies, however it dies.
pub fn die_with_parent() {
    // SAFETY: prctl with PR_SET_PDEATHSIG takes a signal number and touches no memory of ours
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM as libc::c_ulong);
    }
    // the shell may have gone between starting us and the call above
    if unsafe { libc::getppid() } == 1 {
        std::process::exit(0);
    }
}

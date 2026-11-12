//! The shell's helpers for devices, one program with a job per subcommand (each runs as a process
//! of its own, started by the service that talks to it):
//!
//!   pistachio-devices bluetooth [--session]   BlueZ pairing agent; services/Bluetooth.qml
//!   pistachio-devices drives [--session]      mounts removable drives; services/Drives.qml
//!
//! See each module for its lines on stdout and stdin. Both exit when stdin closes, so they never
//! outlive the shell.

mod bluetooth;
mod drives;

fn main() {
    pistachio_lines::die_with_parent();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let session = args.iter().any(|a| a == "--session");
    match args.first().map(String::as_str) {
        Some("bluetooth") => bluetooth::run(session),
        Some("drives") => drives::run(session),
        _ => {
            pistachio_lines::log("usage: pistachio-devices bluetooth|drives [--session]");
            std::process::exit(2);
        }
    }
}

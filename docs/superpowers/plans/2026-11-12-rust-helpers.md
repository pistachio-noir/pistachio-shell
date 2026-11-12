# Rust Helpers Implementation Plan (optimisation, Part B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. No agent stages or commits: each task ends with a commit message as text for the owner.

**Goal:** Replace the always-running Python helpers and udiskie (177 MiB resident) with three small Rust binaries speaking the same protocols, so the QML services change only the command they start.

**Architecture:** One cargo workspace in `rust/`, three binary crates and one tiny shared library crate for the JSON-lines stdin/stdout loop. Each helper is a plain threaded program (no async runtime of our own): a D-Bus connection or sockets on worker threads, one stdin reader that ends the process when the shell goes. Each swap lands only when the helper's existing test passes against the Rust binary; the Python file is deleted in the same task.

**Tech Stack:** Rust 1.99 (cargo installed), `zbus` 6 (blocking API) for D-Bus, `serde`/`serde_json`, `openssl` crate (the system's libssl, already required by the Python helper's certificate step) for LocalSend's HTTPS, `libc` for sockets options and `prctl`. Nothing else without a ledgered reason.

**Spec:** `docs/superpowers/specs/2026-11-12-optimisation-design.md` (step 4, "Calls Claude made"). Parent plan: `docs/superpowers/plans/2026-11-12-optimisation.md`.

**Measured before (12 November):** udiskie 57, polkit-agent.py 32, bluetooth-agent.py 31, localsend.py 29, launcher-tools.py 19, udisksctl monitor 8, pactl 5 = 177 MiB (pactl and launcher-tools stay: 24).

## Global Constraints

- Same stdin/stdout JSON lines, same flags (`--session`; `--port`, `--data`), same exit-when-stdin-closes as each Python helper. Field names, error strings the UI shows ("No PAM with --session" in tests, `org.bluez.Error.Rejected`, …) and event order are copied from the Python docstrings, which are the protocol's reference.
- `pistachio-auth` is alone in its process and never links the network code. PAM starts only when the shell sends a password; a dismissed dialog costs no pam_faillock strike.
- Real password tests: one `pkexec /usr/bin/true` at a time, correct password; never two wrong in a row. `faillock --user $USER` before and after.
- No Bluetooth device disconnected, no Ethernet toggled, no audio route changed. The LocalSend app must not run during its tests (port 53317 is ours); tests use 53318/53319.
- Binaries install to `~/.local/bin` (`install.sh`); services start them by absolute path from `$HOME`, not through PATH. When a binary is missing the service logs one warning naming `install.sh` (as the Python ones name python-gobject today).
- Every helper dies with the shell: stdin EOF ends it, and `PR_SET_PDEATHSIG(SIGTERM)` is set at startup (replaces the `setpriv` wrapper).
- After each swap: `psc restart`, `sh tests/mem.sh`, the helper's RSS into `todos/TODO_12-11-26.md`, hand checks listed unchecked.
- README (requirements: cargo/rustc to build; udiskie and python-gobject's roles updated), CLAUDE.md (helper list, gotchas) and `.gitignore` (`/rust/target/`) change in the task that makes them true.

## Review Focus

1. **polkitd or bluetoothd restarts while a question is open:** the helper must drop the pending requests with the same D-Bus errors, send `lost`, and register again when the daemon returns (`ready`). → unit test of the watch logic with a fake name owner on the session bus (Tasks 2, 3).
2. **PAM asks more than a password** (a second prompt, an info or error line, a fingerprint/OTP module): prompts go out as `prompt` events with `echo`, errors become the `failed` event's `error`. → fake helper-socket test (Task 2).
3. **A drive that is busy, encrypted, read-only, or pulled out without eject:** automount must never crash the helper or block its loop; each case has its toast (or silence) as udiskie does today. → `tests/drives.sh` against a mock UDisks2 on the session bus (Task 4).
4. **Hostile or sloppy LocalSend peers:** file names with `../`, absolute paths, a body shorter or longer than announced, a sender that vanishes mid-file, two senders at once, a wrong session or token. The Python helper's answers (status codes, `receiveFailed` reasons) are the reference. → the existing `tests/localsend.sh` plus the new cases in Task 5.
5. **Half-written JSON or a huge line on stdin, and a closed stdout:** ignored with the same "ignored answer" log; a write error ends the helper quietly, never a panic loop.

---

### Task 1: Workspace, the shared line loop, and tests that take the helper as a parameter

**Files:**
- Create: `rust/Cargo.toml` (workspace, `[profile.release] opt-level = "s"`, `lto = true`, `panic = "abort"`, `strip = true`), `rust/lines/` (lib crate `pistachio-lines`), `rust/.gitignore`-equivalent line in `.gitignore`
- Modify: `tests/polkit-agent.sh`, `tests/bluetooth-agent.sh`, `tests/localsend.sh`, `install.sh`, `README.md`

**Interfaces:**
- Produces (`pistachio-lines`):
  - `pub fn emit(value: &serde_json::Value)` — one line on stdout, flushed, under a lock; a failed write exits the process with status 0.
  - `pub fn log(text: &str)` — one line on stderr.
  - `pub fn read_lines(on_line: impl FnMut(&str))` — blocking; skips blank lines; returns at EOF. Lines over 1 MiB are dropped with `log("ignored answer: line too long")`.
  - `pub fn die_with_parent()` — `prctl(PR_SET_PDEATHSIG, SIGTERM)`.
- Produces (tests): each script reads `HELPER` — a command line, default the Python helper (`python3 -I src/services/<name>.py`) — and runs `$HELPER --session …`.
- Produces (`install.sh`): `helpers()` — if `cargo` exists, `cargo build --release --manifest-path "$repo/rust/Cargo.toml"`, then copies each built binary to `~/.local/bin` (copy, not link: the repo may move); without cargo, a note and the shell still runs (the services warn).

- [ ] **Step 1:** Add `HELPER` to the three test scripts; run each with the default: `all passed` three times (LocalSend's needs the app not running).
- [ ] **Step 2:** Unit tests in `rust/lines`: `read_lines` over a pipe yields lines split across reads, skips blanks, drops an oversized line and carries on; `emit` writes exactly one `\n`-ended line.
- [ ] **Step 3:** `cargo test -p pistachio-lines`: FAIL (not written), implement, PASS.
- [ ] **Step 4:** `install.sh` `helpers()`; run it: builds, nothing to copy yet, exits 0. README build requirement.
- [ ] **Step 5:** Commit text: `new: rust workspace for the shell's helpers`.

### Task 2: `pistachio-auth`

**Files:**
- Create: `rust/auth/` (`src/main.rs`, `src/agent.rs` D-Bus side, `src/pam.rs` polkit's helper side, `src/requests.rs` state)
- Modify: `src/services/Polkit.qml:94` (command), `README.md`, `CLAUDE.md`
- Delete: `src/services/polkit-agent.py`
- Test: `tests/polkit-agent.sh` (unchanged checks, `HELPER=rust/target/release/pistachio-auth`), `rust/auth/tests/pam.rs`

**Interfaces:**
- Consumes: `pistachio-lines`.
- Produces: the protocol in `polkit-agent.py`'s docstring, unchanged. Object path `/pistachio/PolkitAgent`, interface `org.freedesktop.PolicyKit1.AuthenticationAgent`; only polkitd's unique name may call it (anyone with `--session`).
- `pam.rs`: `fn authenticate(user: &str, cookie: &str, on: impl FnMut(PamEvent) -> Option<String>) -> bool` where `PamEvent` is `Prompt { text, echo }`, `Error(text)`, `Info(text)`. It talks to polkit's own helper, as libpolkit-agent does: first the socket `/run/polkit/agent-helper.socket` (polkit 127+, the one installed: 128), else the setuid `/usr/lib/polkit-1/polkit-agent-helper-1 <user>` with the cookie on stdin. Lines read: `PAM_PROMPT_ECHO_OFF`, `PAM_PROMPT_ECHO_ON`, `PAM_ERROR_MSG`, `PAM_TEXT_INFO`, `SUCCESS`, `FAILURE`. No PAM library is linked: the password never meets PAM inside our process.

- [ ] **Step 1:** Read polkit 128's `polkitagentsession.c` and `polkitagenthelper-pam.c` (upstream source, the tag for 128) and write the exact wire format (what is sent first on the socket, line endings, escaping) at the top of `pam.rs`. Do not guess it from memory.
- [ ] **Step 2:** `rust/auth/tests/pam.rs`: a fake helper on a temporary Unix socket (path injected) plays three scripts: password → SUCCESS; password → `PAM_ERROR_MSG` → FAILURE (error text reaches the caller); password → second `PAM_PROMPT_ECHO_ON` → SUCCESS. Plus: helper closes mid-way → `false`, no panic. Run: FAIL.
- [ ] **Step 3:** Implement `pam.rs`; test PASS.
- [ ] **Step 4:** Implement the agent: BeginAuthentication/CancelAuthentication, `user_for` (this user if allowed, else the first named), `requester` (comm vs argv, as the Python), `vendor` (Authority.EnumerateActions over D-Bus), registration for the session (`XDG_SESSION_ID`, else logind's GetSessionByPID) on name-owner changes of `org.freedesktop.PolicyKit1`, `ready`/`lost`, cancel paths. With `--session`: session bus, `ready` carries `name`, a response answers `failed` with "No PAM with --session".
- [ ] **Step 5:** `HELPER=rust/target/release/pistachio-auth bash tests/polkit-agent.sh`: `all passed` (every existing line, same order).
- [ ] **Step 6:** Review Focus 1: a test that owns and drops a fake `org.freedesktop.PolicyKit1` name on the session bus (behind a test-only `--watch-session` flag) and sees `lost`, then `ready`.
- [ ] **Step 7:** Swap `Polkit.qml` to `Quickshell.env("HOME") + "/.local/bin/pistachio-auth"`, `sh install.sh`, `psc restart`. Live: `faillock --user $USER`; `pkexec /usr/bin/true` → dismiss the dialog → count unchanged; again → correct password → authorised. `sh tests/mem.sh`; the helper's RSS into the TODO.
- [ ] **Step 8:** Delete `polkit-agent.py`; README/CLAUDE.md; `tests/system.sh` still passes (Health lists helpers: update its list in `system-tools.py` to the binary).
- [ ] **Step 9:** Commit text: `new: pistachio-auth replaces the python polkit agent`.

### Task 3: `pistachio-devices bluetooth`

**Files:**
- Create: `rust/devices/` (`src/main.rs` subcommands `bluetooth` and `drives`, `src/bluetooth.rs`)
- Modify: `src/services/Bluetooth.qml:265`
- Delete: `src/services/bluetooth-agent.py`
- Test: `tests/bluetooth-agent.sh` with `HELPER="rust/target/release/pistachio-devices bluetooth"`

One binary, two subcommands, run as two processes (each service keeps owning its process and its own stdin protocol; a few MiB each). Ruling recorded here: the spec's table puts both in "pistachio-devices"; it does not say one process.

- [ ] **Step 1:** Implement `org.bluez.Agent1` at `/pistachio/agent` (KeyboardDisplay, RegisterAgent + RequestDefaultAgent on name-owner changes of `org.bluez`), the seven kinds, ids, zero-padded codes, validation of pin (1–16 characters) and passkey (digits, ≤ 999999), `Cancel` → `org.bluez.Error.Canceled` for all pending + `cancel` event.
- [ ] **Step 2:** `HELPER=… bash tests/bluetooth-agent.sh`: `all passed`.
- [ ] **Step 3:** Swap `Bluetooth.qml`, restart; `Bluetooth.agent` true in `tests/harness`'s state (read-only check, no power toggle); RSS into the TODO. Hand check listed: pair a device that shows a code.
- [ ] **Step 4:** Delete `bluetooth-agent.py`. Commit text: `new: pistachio-devices replaces the python pairing agent`.

### Task 4: `pistachio-devices drives` (udiskie and `udisksctl monitor`)

**Files:**
- Create: `rust/devices/src/drives.rs`, `tests/drives.sh`, `tests/drives-mock.py` (a mock `org.freedesktop.UDisks2` on the session bus, python-gobject, test-only)
- Modify: `src/services/Drives.qml` (one Process instead of two), `src/services/system-tools.py` (Health's dependency list), `README.md`, `CLAUDE.md`

**Interfaces:**
- Produces, on stdout: `{"event":"ready"}`, `{"event":"changed"}` after any UDisks object or mount change (Drives.qml restarts its 400 ms `reading` timer on it, exactly as it does per `udisksctl monitor` line today; `lsblk` and the eject path in `system-tools.py` stay as they are).
- Behaviour (udiskie `--automount --notify --no-tray`, scope from the spec): on start and on `InterfacesAdded`, a block device with a filesystem that is removable/hotplug, not hidden (`HintIgnore`/`HintSystem`), not already mounted → `Filesystem.Mount({})`. Toasts through `org.freedesktop.Notifications` (app name "Drives", icon `drive-removable-media`): mounted "<label> mounted on <path>" with action **Open** (`xdg-open <path>`), unmounted, removed, failed (with UDisks' message). An encrypted (`Encrypted` interface, locked) device: one toast "<label> is encrypted" with **Open in the file manager**; no unlock.
- `--session`: talks to the mock on the session bus and prints toasts as `{"event":"toast",…}` lines instead of sending them.

- [ ] **Step 1:** Before writing: record udiskie's exact toast texts and timing from its source (2.7.0, installed) and one real plug-in if the owner has a stick at hand (else listed as hand check); the Rust toasts copy the wording.
- [ ] **Step 2:** `tests/drives-mock.py` + `tests/drives.sh`: mock exposes ObjectManager with scriptable block devices. Cases: present at start → mounted + toast; added later → mounted; `HintSystem` → ignored; already mounted → no second mount; Mount fails (busy) → failed toast, helper alive; encrypted → encrypted toast, no Mount/Unlock call; removed while mounted → removed toast; every change → a `changed` line; stdin EOF → exit. Run with a stub helper: FAIL.
- [ ] **Step 3:** Implement; `sh tests/drives.sh`: PASS.
- [ ] **Step 4:** Swap `Drives.qml`; restart; `pgrep udiskie` empty, `pgrep udisksctl` empty; launcher Eject rows still list a mounted drive (hand check with a real stick; busy-eject flow unchanged, it lives in `system-tools.py`).
- [ ] **Step 5:** README: udiskie no longer needed (and "don't start another one" note updated); CLAUDE.md. RSS into the TODO.
- [ ] **Step 6:** Commit text: `new: pistachio-devices mounts drives, replacing udiskie`.

### Task 5: `pistachio-localsend`

**Files:**
- Create: `rust/localsend/` (`src/main.rs` commands and state, `src/discovery.rs` multicast + address sweep, `src/http.rs` minimal HTTP/1.1 over `openssl::ssl::SslStream`, `src/server.rs` receive side, `src/send.rs`, `src/files.rs` inspect/paste/safe paths)
- Modify: `src/services/LocalSend.qml:312`
- Delete: `src/services/localsend.py`
- Test: `tests/localsend.sh` with `HELPER`, both pairings

**Interfaces:**
- Produces: the protocol in `localsend.py`'s docstring, unchanged; `--port`, `--data`. The certificate and key already in `--data` are reused (the fingerprint must stay the same, or phones stop recognising the PC and "accept known" breaks); only when missing is one made, with the same `openssl req` command as today.
- HTTP: Content-Length bodies only, as the Python server (it never decoded chunked either); one thread per connection; 256 KiB chunks; peer certificates are not verified (LocalSend devices use self-made ones).

- [ ] **Step 1:** Read `localsend.py` whole and list every status code, timeout, state name and edge rule (safe_path, peer_gone, auto-accept for known senders, busy/pin answers, legacy sweep) as a checklist at the top of `main.rs`.
- [ ] **Step 2:** Extend `tests/localsend.sh` first, against Python (must pass there): a `../` file name lands inside the folder; a sender closing mid-file gives `receiveFailed` "lost" and no partial file left behind (or whatever Python does — the test pins today's behaviour); a second sender during a transfer is refused as today; a wrong token is refused.
- [ ] **Step 3:** Implement in the order discovery → info/register → receive → send → inspect/paste, running the matching part of the test after each.
- [ ] **Step 4:** `tests/localsend.sh` three ways: Rust↔Rust, Rust→Python, Python→Rust: `all passed` each.
- [ ] **Step 5:** Swap `LocalSend.qml` (no `setpriv`: the helper sets its own parent-death signal); restart; fingerprint in quick settings unchanged; RSS into the TODO. Hand check listed: a file each way with the phone, a text, a decline.
- [ ] **Step 6:** Delete `localsend.py`. Commit text: `new: pistachio-localsend replaces the python localsend helper`.

### Task 6: Wrap-up

- [ ] **Step 1:** `psc restart`; `sh tests/mem.sh scenario`; helper table before/after into the TODO.
- [ ] **Step 2:** All of: `tests/polkit-agent.sh`, `tests/bluetooth-agent.sh`, `tests/drives.sh`, `tests/localsend.sh`, `tests/system.sh`, `tests/settings.sh`, `tests/ipc-surface.sh`, `cargo test --workspace`, `cargo clippy --workspace` clean.
- [ ] **Step 3:** README, CLAUDE.md (decision dated 12 November, helper list, gotchas met), `docs/plan.md`.
- [ ] **Step 4:** Fresh-context review of the whole diff (code-reviewer, most capable model) with the Review Focus list; fix Critical/Important with a failing test first.
- [ ] **Step 5:** Report: numbers, what the owner must test by hand, full commit message as text.

`launcher-tools.py` (19 MiB) is not in this plan: it follows only if the owner asks after seeing the numbers.

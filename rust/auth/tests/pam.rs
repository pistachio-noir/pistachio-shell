//! The conversation with polkit's helper, against a stand-in helper on a socket of our own.

use pistachio_auth::pam::{unescape, Event, Session};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::thread;

/// A stand-in helper: checks the user and cookie lines, then plays `script`: each `(says, expects)`
/// writes `says` and, when `expects` is given, reads one line and checks it. Returns the socket.
fn helper(name: &str, script: Vec<(&'static str, Option<&'static str>)>) -> (PathBuf, thread::JoinHandle<()>) {
    let path = std::env::temp_dir().join(format!("pistachio-auth-test-{}-{name}.sock", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).unwrap();
    let played = thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut reader = BufReader::new(stream.try_clone().unwrap());
        let mut writer = stream;
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        assert_eq!(line, "sx\n");
        line.clear();
        reader.read_line(&mut line).unwrap();
        assert_eq!(line, "cookie-1\n");
        for (says, expects) in script {
            writer.write_all(says.as_bytes()).unwrap();
            if let Some(expected) = expects {
                line.clear();
                reader.read_line(&mut line).unwrap();
                assert_eq!(line, expected);
            }
        }
    });
    (path, played)
}

fn start(socket: &Path) -> Session {
    Session::start("sx", "cookie-1", socket, Path::new("/nonexistent/helper")).unwrap().0
}

#[test]
fn the_password_is_asked_hidden_and_success_is_reported() {
    let (socket, played) = helper("ok", vec![("PAM_PROMPT_ECHO_OFF Password: \n", Some("hunter2\n")), ("SUCCESS\n", None)]);
    let mut seen = Vec::new();
    let gained = start(&socket).run(|event| {
        seen.push(event);
        Some("hunter2".into())
    });
    played.join().unwrap();
    assert!(gained);
    assert_eq!(seen, [Event::Prompt { text: "Password: ".into(), echo: false }]);
}

#[test]
fn pams_error_reaches_the_caller_before_the_failure() {
    let (socket, played) = helper(
        "wrong",
        vec![("PAM_PROMPT_ECHO_OFF Password: \n", Some("nope\n")), ("PAM_ERROR_MSG Account locked for 10 minutes\\nTry later\n", None), ("FAILURE\n", None)],
    );
    let mut seen = Vec::new();
    let gained = start(&socket).run(|event| {
        seen.push(event);
        Some("nope".into())
    });
    played.join().unwrap();
    assert!(!gained);
    assert_eq!(seen[1], Event::Error("Account locked for 10 minutes\nTry later".into()));
}

#[test]
fn a_second_question_may_show_its_answer() {
    let (socket, played) = helper(
        "otp",
        vec![
            ("PAM_PROMPT_ECHO_OFF Password: \n", Some("hunter2\n")),
            ("PAM_TEXT_INFO A code was sent\n", None),
            ("PAM_PROMPT_ECHO_ON Verification code: \n", Some("123456\n")),
            ("SUCCESS\n", None),
        ],
    );
    let mut seen = Vec::new();
    let gained = start(&socket).run(|event| {
        let answer = matches!(&event, Event::Prompt { echo: true, .. }).then(|| "123456".to_string()).or(Some("hunter2".into()));
        seen.push(event);
        answer
    });
    played.join().unwrap();
    assert!(gained);
    assert_eq!(seen[1], Event::Info("A code was sent".into()));
    assert_eq!(seen[2], Event::Prompt { text: "Verification code: ".into(), echo: true });
}

#[test]
fn a_helper_that_goes_away_is_a_failure_not_a_crash() {
    let (socket, played) = helper("gone", vec![("PAM_PROMPT_ECHO_OFF Password: \n", Some("hunter2\n"))]);
    let gained = start(&socket).run(|_| Some("hunter2".into()));
    played.join().unwrap();
    assert!(!gained);
}

#[test]
fn giving_up_at_a_question_ends_it_without_an_answer() {
    let (socket, played) = helper("dismiss", vec![("PAM_PROMPT_ECHO_OFF Password: \n", None)]);
    let gained = start(&socket).run(|_| None);
    played.join().unwrap();
    assert!(!gained);
}

#[test]
fn cancelling_from_another_thread_ends_a_waiting_session() {
    let path = std::env::temp_dir().join(format!("pistachio-auth-test-{}-cancel.sock", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).unwrap();
    let held = thread::spawn(move || listener.accept().unwrap().0); // says nothing, keeps the connection
    let (session, canceller) = Session::start("sx", "cookie-1", &path, Path::new("/nonexistent/helper")).unwrap();
    let running = thread::spawn(move || session.run(|_| Some(String::new())));
    let _stream = held.join().unwrap();
    canceller.cancel();
    assert!(!running.join().unwrap());
}

#[test]
fn a_line_break_in_the_cookie_is_refused() {
    assert!(Session::start("sx", "a\nb", Path::new("/nonexistent/socket"), Path::new("/nonexistent/helper")).is_err());
}

#[test]
fn escapes_are_undone_as_g_strcompress_does() {
    assert_eq!(unescape(r#"a\tb\\c\"d\101\n"#), "a\tb\\c\"dA\n");
    assert_eq!(unescape("Has\\305\\202o: "), "Hasło: ");
    assert_eq!(unescape("ends with \\"), "ends with \\");
}

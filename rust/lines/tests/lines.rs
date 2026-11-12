use pistachio_lines::{read_lines_from, write_line, MAX_LINE};
use std::io::Read;

/// Hands out its data a few bytes at a time, as a pipe may.
struct Dribble<'a>(&'a [u8], usize);

impl Read for Dribble<'_> {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        let n = self.1.min(self.0.len()).min(buffer.len());
        buffer[..n].copy_from_slice(&self.0[..n]);
        self.0 = &self.0[n..];
        Ok(n)
    }
}

fn lines_of(input: impl Read) -> Vec<String> {
    let mut seen = Vec::new();
    read_lines_from(input, |line| seen.push(line.to_string()));
    seen
}

#[test]
fn lines_split_across_reads_arrive_whole() {
    let data = b"{\"id\": 1}\n{\"id\": 2, \"accept\": true}\n";
    assert_eq!(lines_of(Dribble(data, 3)), ["{\"id\": 1}", "{\"id\": 2, \"accept\": true}"]);
}

#[test]
fn blank_lines_are_skipped_and_a_last_line_without_newline_counts() {
    assert_eq!(lines_of(&b"\n  \r\none\r\n\ntwo"[..]), ["one", "two"]);
}

#[test]
fn an_oversized_line_is_dropped_and_reading_carries_on() {
    let mut data = vec![b'x'; MAX_LINE + 4096];
    data.extend_from_slice(b"\nafter\n");
    assert_eq!(lines_of(Dribble(&data, 7000)), ["after"]);
}

#[test]
fn a_line_of_exactly_the_limit_is_kept() {
    let mut data = vec![b'y'; MAX_LINE - 1];
    data.push(b'\n');
    data.extend_from_slice(b"next\n");
    let seen = lines_of(&data[..]);
    assert_eq!(seen.len(), 2);
    assert_eq!(seen[0].len(), MAX_LINE - 1);
    assert_eq!(seen[1], "next");
}

#[test]
fn bytes_that_are_not_text_are_skipped() {
    assert_eq!(lines_of(&b"\xff\xfe\nfine\n"[..]), ["fine"]);
}

#[test]
fn an_event_is_one_newline_ended_line() {
    let mut out = Vec::new();
    write_line(&mut out, &serde_json::json!({"event": "ready", "text": "two\nlines"})).unwrap();
    assert_eq!(out.iter().filter(|b| **b == b'\n').count(), 1);
    assert_eq!(out.last(), Some(&b'\n'));
    let back: serde_json::Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(back["text"], "two\nlines");
}

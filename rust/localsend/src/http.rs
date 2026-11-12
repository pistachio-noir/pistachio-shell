//! As much HTTP/1.1 as LocalSend needs, over TLS or plain TCP: requests and answers with a
//! Content-Length body, one after another on a connection.

use std::collections::HashMap;
use std::io::{self, BufRead, Read, Write};
use std::net::TcpStream;

use openssl::ssl::SslStream;

const MAX_LINE: usize = 64 * 1024;
const MAX_HEADERS: usize = 100;
/// The most of an answer's body that is read: LocalSend's answers are a few hundred bytes of JSON,
/// and a device on the network must not be able to make us reserve what it likes.
pub const MAX_BODY: usize = 4 * 1024 * 1024;

pub enum Stream {
    Plain(TcpStream),
    Tls(Box<SslStream<TcpStream>>),
}

impl Read for Stream {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        match self {
            Stream::Plain(s) => s.read(buffer),
            Stream::Tls(s) => s.read(buffer),
        }
    }
}

impl Write for Stream {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        match self {
            Stream::Plain(s) => s.write(buffer),
            Stream::Tls(s) => s.write(buffer),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match self {
            Stream::Plain(s) => s.flush(),
            Stream::Tls(s) => s.flush(),
        }
    }
}

fn bad(text: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, text.to_string())
}

/// One line without its line break; `None` when the connection ended before any byte.
fn read_line(reader: &mut impl BufRead) -> io::Result<Option<String>> {
    let mut line = Vec::new();
    let read = reader.by_ref().take(MAX_LINE as u64 + 1).read_until(b'\n', &mut line)?;
    if read == 0 {
        return Ok(None);
    }
    if line.last() != Some(&b'\n') {
        return Err(bad(if line.len() > MAX_LINE { "a line too long" } else { "the connection ended mid-line" }));
    }
    line.pop();
    if line.last() == Some(&b'\r') {
        line.pop();
    }
    Ok(Some(String::from_utf8_lossy(&line).into_owned()))
}

/// Header lines up to the empty one, names in lower case.
fn read_headers(reader: &mut impl BufRead) -> io::Result<HashMap<String, String>> {
    let mut headers = HashMap::new();
    let mut lines = 0; // every line counts, whatever is in it
    loop {
        let line = read_line(reader)?.ok_or_else(|| bad("the connection ended in the headers"))?;
        if line.is_empty() {
            return Ok(headers);
        }
        lines += 1;
        if lines > MAX_HEADERS {
            return Err(bad("too many headers"));
        }
        if let Some((name, value)) = line.split_once(':') {
            headers.insert(name.trim().to_ascii_lowercase(), value.trim().to_string());
        }
    }
}

/// The start of a request: its line and headers. The body is still to be read.
pub struct Head {
    pub method: String,
    pub path: String,
    pub query: HashMap<String, String>,
    pub headers: HashMap<String, String>,
    pub keep_alive: bool,
}

impl Head {
    /// Content-Length, when there is a valid one.
    pub fn length(&self) -> Option<u64> {
        self.headers.get("content-length")?.parse().ok()
    }
}

/// The next request on a connection; `None` when the other side closed it instead.
pub fn read_request(reader: &mut impl BufRead) -> io::Result<Option<Head>> {
    let Some(line) = read_line(reader)? else { return Ok(None) };
    let mut words = line.split_whitespace();
    let (Some(method), Some(target), Some(version)) = (words.next(), words.next(), words.next()) else { return Err(bad("not a request")) };
    let headers = read_headers(reader)?;
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    let query = query.split_once('#').map_or(query, |(q, _)| q);
    let connection = headers.get("connection").map(|c| c.to_ascii_lowercase()).unwrap_or_default();
    let keep_alive = if version == "HTTP/1.1" { connection != "close" } else { connection == "keep-alive" };
    Ok(Some(Head { method: method.to_string(), path: path.to_string(), query: parse_query(query), headers, keep_alive }))
}

/// Answers a request, with a JSON body or none.
pub fn write_response(writer: &mut impl Write, status: u16, body: Option<&serde_json::Value>) -> io::Result<()> {
    let data = body.map(|b| b.to_string().into_bytes()).unwrap_or_default();
    let reason = match status {
        200 => "OK",
        204 => "No Content",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        501 => "Not Implemented",
        _ => "Status",
    };
    let mut message = format!("HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n", data.len()).into_bytes();
    message.extend_from_slice(&data);
    writer.write_all(&message)?;
    writer.flush()
}

/// The start of a request we send; the body, `length` bytes, follows.
pub fn write_request(writer: &mut impl Write, target: &str, host: &str, content_type: &str, length: u64) -> io::Result<()> {
    writer.write_all(format!("POST {target} HTTP/1.1\r\nHost: {host}\r\nAccept-Encoding: identity\r\nContent-Length: {length}\r\nContent-Type: {content_type}\r\n\r\n").as_bytes())
}

/// An answer to a request we sent: its status and whole body.
pub fn read_response(reader: &mut impl BufRead) -> io::Result<(u16, Vec<u8>)> {
    let line = read_line(reader)?.ok_or_else(|| bad("no answer"))?;
    let status: u16 = line.split_whitespace().nth(1).and_then(|s| s.parse().ok()).ok_or_else(|| bad("not an answer"))?;
    let headers = read_headers(reader)?;
    let mut body = Vec::new();
    if status == 204 || status == 304 || (100..200).contains(&status) {
        return Ok((status, body));
    }
    if headers.get("transfer-encoding").is_some_and(|t| t.to_ascii_lowercase().contains("chunked")) {
        loop {
            let size = read_line(reader)?.ok_or_else(|| bad("the answer ended early"))?;
            let size = usize::from_str_radix(size.split(';').next().unwrap_or_default().trim(), 16).map_err(|_| bad("a bad chunk"))?;
            if size == 0 {
                while read_line(reader)?.is_some_and(|l| !l.is_empty()) {}
                return Ok((status, body));
            }
            if size > MAX_BODY - body.len() {
                return Err(bad("the answer is too long"));
            }
            let at = body.len();
            body.resize(at + size, 0);
            reader.read_exact(&mut body[at..])?;
            read_line(reader)?;
        }
    }
    match headers.get("content-length").and_then(|l| l.parse::<u64>().ok()) {
        Some(length) => {
            if length > MAX_BODY as u64 {
                return Err(bad("the answer is too long"));
            }
            reader.take(length).read_to_end(&mut body)?;
            if (body.len() as u64) < length {
                return Err(bad("the answer ended early"));
            }
        }
        None => {
            reader.take(MAX_BODY as u64 + 1).read_to_end(&mut body)?;
            if body.len() > MAX_BODY {
                return Err(bad("the answer is too long"));
            }
        }
    }
    Ok((status, body))
}

/// %XX and, in a query, + for a space.
pub fn percent_decode(text: &str, plus: bool) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = |b: u8| (b as char).to_digit(16);
        match bytes[i] {
            b'%' if i + 2 < bytes.len() && hex(bytes[i + 1]).is_some() && hex(bytes[i + 2]).is_some() => {
                out.push((hex(bytes[i + 1]).unwrap() * 16 + hex(bytes[i + 2]).unwrap()) as u8);
                i += 3;
                continue;
            }
            b'+' if plus => out.push(b' '),
            other => out.push(other),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// A query's pairs; one without a value is dropped, the last of a name wins.
pub fn parse_query(query: &str) -> HashMap<String, String> {
    query
        .split('&')
        .filter_map(|pair| pair.split_once('='))
        .filter(|(_, value)| !value.is_empty())
        .map(|(name, value)| (percent_decode(name, true), percent_decode(value, true)))
        .collect()
}

/// name=value&… with everything but letters, digits and _.-~ escaped.
pub fn encode_query(pairs: &[(&str, &str)]) -> String {
    let quote = |text: &str| {
        let mut out = String::new();
        for byte in text.bytes() {
            match byte {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'_' | b'.' | b'-' | b'~' => out.push(byte as char),
                b' ' => out.push('+'),
                other => out.push_str(&format!("%{other:02X}")),
            }
        }
        out
    };
    pairs.iter().map(|(name, value)| format!("{}={}", quote(name), quote(value))).collect::<Vec<_>>().join("&")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::BufReader;

    #[test]
    fn a_request_is_read_with_its_query_and_headers() {
        let text = b"POST /api/localsend/v2/upload?sessionId=ab&fileId=0-1f&token=x%20y&empty= HTTP/1.1\r\nContent-Length: 12\r\nHost: 1.2.3.4\r\n\r\nhello";
        let head = read_request(&mut BufReader::new(&text[..])).unwrap().unwrap();
        assert_eq!((head.method.as_str(), head.path.as_str()), ("POST", "/api/localsend/v2/upload"));
        assert_eq!(head.query["token"], "x y");
        assert!(!head.query.contains_key("empty"));
        assert_eq!(head.length(), Some(12));
        assert!(head.keep_alive);
    }

    #[test]
    fn a_closed_connection_is_no_request_and_half_a_line_is_an_error() {
        assert!(read_request(&mut BufReader::new(&b""[..])).unwrap().is_none());
        assert!(read_request(&mut BufReader::new(&b"POST /x HT"[..])).is_err());
        assert!(read_request(&mut BufReader::new(&b"nonsense\r\n\r\n"[..])).is_err());
    }

    #[test]
    fn a_header_line_without_end_is_refused_not_swallowed() {
        let mut text = b"GET / HTTP/1.1\r\nX: ".to_vec();
        text.extend(std::iter::repeat(b'a').take(MAX_LINE + 10));
        assert!(read_request(&mut BufReader::new(&text[..])).is_err());
    }

    #[test]
    fn answers_are_read_by_length_in_chunks_or_to_the_end() {
        let read = |text: &[u8]| read_response(&mut BufReader::new(text)).unwrap();
        assert_eq!(read(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}extra"), (200, b"{}".to_vec()));
        assert_eq!(read(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n"), (200, b"abcde".to_vec()));
        assert_eq!(read(b"HTTP/1.0 403 Forbidden\r\n\r\nno"), (403, b"no".to_vec()));
        assert_eq!(read(b"HTTP/1.1 204 No Content\r\n\r\n"), (204, vec![]));
        assert!(read_response(&mut BufReader::new(&b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nshort"[..])).is_err());
    }

    #[test]
    fn an_answer_that_claims_or_sends_too_much_is_refused_before_it_is_stored() {
        let read = |text: &[u8]| read_response(&mut BufReader::new(text));
        assert!(read(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffff\r\nabc").is_err());
        assert!(read(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7fffffff\r\nabc").is_err());
        assert!(read(b"HTTP/1.1 200 OK\r\nContent-Length: 99999999999\r\n\r\nabc").is_err());
        let mut endless = b"HTTP/1.0 200 OK\r\n\r\n".to_vec();
        endless.resize(endless.len() + MAX_BODY + 10, b'x');
        assert!(read(&endless).is_err());
    }

    #[test]
    fn header_lines_are_counted_whatever_they_hold() {
        let mut text = b"GET / HTTP/1.1\r\n".to_vec();
        for _ in 0..MAX_HEADERS + 5 {
            text.extend_from_slice(b"no colon here\r\n");
        }
        text.extend_from_slice(b"\r\n");
        assert!(read_request(&mut BufReader::new(&text[..])).is_err());
    }

    #[test]
    fn queries_round_trip() {
        let encoded = encode_query(&[("sessionId", "a b&c"), ("token", "ż/1")]);
        assert_eq!(encoded, "sessionId=a+b%26c&token=%C5%BC%2F1");
        let back = parse_query(&encoded);
        assert_eq!((back["sessionId"].as_str(), back["token"].as_str()), ("a b&c", "ż/1"));
        assert_eq!(percent_decode("100%", false), "100%");
        assert_eq!(percent_decode("a+b%2", false), "a+b%2");
    }
}

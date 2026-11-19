//! `psc swatch COLOUR PATH`: a 64 px square of one colour as a PNG, for the colour picker's
//! notification (services/Screenshots.qml). Python's swatch.py until 19 November 2026.
fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 { crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 }; }
    }
    !crc
}

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for &x in data { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
    (b << 16) | a
}

/// zlib with "stored" deflate blocks: no compression crate needed for 12 KiB.
fn zlib_stored(data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x78, 0x01];
    let blocks: Vec<&[u8]> = data.chunks(65535).collect();
    for (i, block) in blocks.iter().enumerate() {
        out.push(if i + 1 == blocks.len() { 1 } else { 0 });
        let len = block.len() as u16;
        out.extend(len.to_le_bytes());
        out.extend((!len).to_le_bytes());
        out.extend_from_slice(block);
    }
    out.extend(adler32(data).to_be_bytes());
    out
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend((data.len() as u32).to_be_bytes());
    let mut body = kind.to_vec();
    body.extend_from_slice(data);
    out.extend_from_slice(&body);
    out.extend(crc32(&body).to_be_bytes());
}

pub fn png(rgb: [u8; 3]) -> Vec<u8> {
    let mut rows = Vec::with_capacity(64 * 193);
    for _ in 0..64 {
        rows.push(0); // no filter
        for _ in 0..64 { rows.extend_from_slice(&rgb); }
    }
    let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
    chunk(&mut out, b"IHDR", &[0, 0, 0, 64, 0, 0, 0, 64, 8, 2, 0, 0, 0]);
    chunk(&mut out, b"IDAT", &zlib_stored(&rows));
    chunk(&mut out, b"IEND", &[]);
    out
}

/// "#9fd88a" (or with an alpha byte after it, which is ignored) → [0x9f, 0xd8, 0x8a]
pub fn parse(colour: &str) -> Option<[u8; 3]> {
    let hex = colour.trim_start_matches('#');
    let byte = |i: usize| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok();
    Some([byte(0)?, byte(2)?, byte(4)?])
}

pub fn main(args: &[String]) -> i32 {
    match (args.first().and_then(|c| parse(c)), args.get(1)) {
        (Some(rgb), Some(path)) if args.len() == 2 => match std::fs::write(path, png(rgb)) {
            Ok(()) => 0,
            Err(e) => { eprintln!("psc swatch: {e}"); 1 }
        },
        _ => { eprintln!("usage: psc swatch '#rrggbb' PATH"); 1 }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_valid_64px_png_of_the_colour() {
        let data = png([0x9f, 0xd8, 0x8a]);
        assert_eq!(&data[..8], b"\x89PNG\r\n\x1a\n");
        assert_eq!(&data[12..16], b"IHDR");
        assert_eq!(&data[16..29], &[0, 0, 0, 64, 0, 0, 0, 64, 8, 2, 0, 0, 0]);
        assert_eq!(&data[data.len() - 8..data.len() - 4], b"IEND");
        assert_eq!(parse("#9fd88a"), Some([0x9f, 0xd8, 0x8a]));
        assert_eq!(parse("9FD88AFF"), Some([0x9f, 0xd8, 0x8a]), "an alpha byte is ignored, as swatch.py's [:6]");
        assert_eq!(parse("#zz"), None);
    }
}

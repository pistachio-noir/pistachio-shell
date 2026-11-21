//! A VS Code extension package (.vsix) for the shell's theme (`psc theme`, VS Code; 21 November 2026).
//! VS Code lists only extensions it recorded in its extensions.json, so a folder copied in by hand never
//! showed up; `code --install-extension FILE.vsix` installs and records it. A .vsix is a zip: the
//! extension under `extension/`, plus `extension.vsixmanifest` and `[Content_Types].xml`. Two small
//! JSON themes need no compression, so this writes a stored (uncompressed) zip with CRC-32s.

/// CRC-32 (IEEE, as zip uses), bit by bit: a few KB of theme, once per install.
pub fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

/// A zip of `files` (path, content), stored, with a fixed timestamp (1 January 2026) so the same
/// input always gives the same bytes.
pub fn zip(files: &[(&str, &[u8])]) -> Vec<u8> {
    const TIME: u16 = 0; // 00:00:00
    const DATE: u16 = ((2026 - 1980) << 9) | (1 << 5) | 1;
    let mut out = Vec::new();
    let mut central = Vec::new();
    for (name, data) in files {
        let offset = out.len() as u32;
        let (crc, size, name_len) = (crc32(data), data.len() as u32, name.len() as u16);
        // local file header
        out.extend(0x0403_4b50u32.to_le_bytes());
        out.extend(20u16.to_le_bytes()); // version needed
        out.extend(0x0800u16.to_le_bytes()); // flags: names are UTF-8
        out.extend(0u16.to_le_bytes()); // stored
        out.extend(TIME.to_le_bytes());
        out.extend(DATE.to_le_bytes());
        out.extend(crc.to_le_bytes());
        out.extend(size.to_le_bytes());
        out.extend(size.to_le_bytes());
        out.extend(name_len.to_le_bytes());
        out.extend(0u16.to_le_bytes()); // no extra field
        out.extend(name.as_bytes());
        out.extend(*data);
        // its central directory entry
        central.extend(0x0201_4b50u32.to_le_bytes());
        central.extend(20u16.to_le_bytes()); // made by
        central.extend(20u16.to_le_bytes()); // version needed
        central.extend(0x0800u16.to_le_bytes());
        central.extend(0u16.to_le_bytes());
        central.extend(TIME.to_le_bytes());
        central.extend(DATE.to_le_bytes());
        central.extend(crc.to_le_bytes());
        central.extend(size.to_le_bytes());
        central.extend(size.to_le_bytes());
        central.extend(name_len.to_le_bytes());
        central.extend([0u8; 8]); // extra, comment, disk start, internal attributes
        central.extend(0u32.to_le_bytes()); // external attributes
        central.extend(offset.to_le_bytes());
        central.extend(name.as_bytes());
    }
    let (start, length, count) = (out.len() as u32, central.len() as u32, files.len() as u16);
    out.extend(central);
    // end of central directory
    out.extend(0x0605_4b50u32.to_le_bytes());
    out.extend([0u8; 4]); // this disk, the directory's disk
    out.extend(count.to_le_bytes());
    out.extend(count.to_le_bytes());
    out.extend(length.to_le_bytes());
    out.extend(start.to_le_bytes());
    out.extend(0u16.to_le_bytes()); // no comment
    out
}

/// The .vsix of an extension: `package.json` and the other files, relative to the extension folder.
pub fn package(publisher: &str, name: &str, version: &str, display: &str, files: &[(&str, &[u8])]) -> Vec<u8> {
    let manifest = format!(r#"<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="{name}" Version="{version}" Publisher="{publisher}" />
    <DisplayName>{display}</DisplayName>
    <Description xml:space="preserve">{display}</Description>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.70.0" />
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
"#);
    let types = r#"<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json" /><Default Extension=".vsixmanifest" ContentType="text/xml" /></Types>
"#;
    let names: Vec<String> = files.iter().map(|(path, _)| format!("extension/{path}")).collect();
    let mut entries: Vec<(&str, &[u8])> = vec![("[Content_Types].xml", types.as_bytes()), ("extension.vsixmanifest", manifest.as_bytes())];
    entries.extend(files.iter().zip(&names).map(|((_, data), name)| (name.as_str(), *data)));
    zip(&entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crc_and_zip() {
        assert_eq!(crc32(b""), 0);
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926, "the standard check value");
        let z = zip(&[("a.txt", b"hello"), ("dir/b.json", b"{}")]);
        assert_eq!(&z[..4], &[0x50, 0x4b, 0x03, 0x04]);
        let end = &z[z.len() - 22..];
        assert_eq!(&end[..4], &[0x50, 0x4b, 0x05, 0x06], "end of central directory last");
        assert_eq!(u16::from_le_bytes([end[10], end[11]]), 2);
        assert_eq!(zip(&[("a", b"x")]), zip(&[("a", b"x")]), "same input, same bytes");
        // an independent reader, when there is one: Python's zipfile (dev only)
        let dir = std::env::temp_dir().join(format!("psc-vsix-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("t.vsix");
        std::fs::write(&file, package("pub", "theme", "1.0.0", "Theme", &[("package.json", b"{\"name\":\"theme\"}"), ("themes/x.json", b"{}")])).unwrap();
        if let Ok(out) = std::process::Command::new("python3").args(["-I", "-c",
            "import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; print(sorted(z.namelist())); print(z.read('extension/package.json').decode())"]).arg(&file).output() {
            let text = String::from_utf8_lossy(&out.stdout);
            assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
            assert!(text.contains("'[Content_Types].xml', 'extension.vsixmanifest', 'extension/package.json', 'extension/themes/x.json'"), "{text}");
            assert!(text.contains("{\"name\":\"theme\"}"), "{text}");
        }
        let _ = std::fs::remove_dir_all(dir);
    }
}

//! `psc log --errors`: errors and warnings only, without the noise that's always there.
/// Noise that shows up in every log and isn't about the shell's own code.
const NOISE: &[&str] = &["qt.qpa.wayland.textinput", "Ignoring sourceSize request for image url that came from grabToImage"];

pub fn keep(line: &str) -> bool {
    let t = line.trim_start();
    (t.starts_with("ERROR") || t.starts_with("FATAL") || t.starts_with("WARN") || t.starts_with("CRITICAL"))
        && !NOISE.iter().any(|n| line.contains(n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_errors_filter() {
        assert!(keep("  ERROR: Failed to load configuration"));
        assert!(keep(" FATAL quickshell: boom"));
        assert!(keep("  WARN scene: @services/NightLight.qml[25:5]: Unable to assign [undefined] to bool"));
        assert!(!keep("  INFO: Configuration Loaded"));
        assert!(!keep("  WARN qt.qpa.wayland.textinput: virtual void QtWaylandClient::QWaylandTextInputv3::disableSurface"));
        assert!(!keep("  WARN: Ignoring sourceSize request for image url that came from grabToImage. Use the targetSize"));
        assert!(!keep(""));
    }
}

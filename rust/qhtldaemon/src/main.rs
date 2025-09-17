use anyhow::Result;
use qhtlcore::{config::parse_config_file, version::read_version_file};
use time::OffsetDateTime;

fn main() -> Result<()> {
    // Load version and config
    let version_file = "/etc/qhtlfirewall/version.txt";
    let version = read_version_file(version_file).unwrap_or_else(|_| "0.0".to_string());
    let cfg_path = "/etc/qhtlfirewall/qhtlfirewall.conf";
    let cfg = match parse_config_file(cfg_path) {
        Ok(m) => m,
        Err(_) => Default::default(),
    };

    // Compose a simple startup log line similar to Perl
    let hostname = hostname::get().unwrap_or_default().to_string_lossy().to_string();
    let now = OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339).unwrap_or_default();
    println!("{} daemon started on {} - qhtlfirewall v{}", now, hostname, version);

    // Minimal feature flags from config (optional future use)
    let _lf_daemon = cfg.get("LF_DAEMON").map(|s| s == "1").unwrap_or(false);

    Ok(())
}

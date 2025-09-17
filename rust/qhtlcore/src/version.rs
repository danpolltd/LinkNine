use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

/// Read a version string from a file and normalize it to a numeric string.
/// Accepts values like "2.0" or "v2.0"; returns "2.0".
pub fn read_version_file<P: AsRef<Path>>(path: P) -> Result<String> {
    let raw = fs::read_to_string(&path)
        .with_context(|| format!("reading version file: {}", path.as_ref().display()))?;
    Ok(normalize_version(raw.trim()))
}

/// Normalize a version string, stripping an optional leading 'v' or 'V'.
pub fn normalize_version(s: &str) -> String {
    let t = s.trim();
    let t = t.strip_prefix('v').or_else(|| t.strip_prefix('V')).unwrap_or(t);
    t.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_variants() {
        assert_eq!(normalize_version("2.0"), "2.0");
        assert_eq!(normalize_version("v2.0"), "2.0");
        assert_eq!(normalize_version(" V2.0 \n"), "2.0");
    }
}

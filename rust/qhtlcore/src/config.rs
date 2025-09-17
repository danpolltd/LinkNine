use anyhow::{Context, Result};
use regex::Regex;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// Parse a qhtlfirewall.conf-style file into key/value pairs.
/// Supports lines like: KEY = "value" or KEY = value, with trailing comments allowed.
pub fn parse_config_file<P: AsRef<Path>>(path: P) -> Result<HashMap<String, String>> {
    let content = fs::read_to_string(&path)
        .with_context(|| format!("reading config file: {}", path.as_ref().display()))?;
    parse_config_str(&content)
}

/// Parse configuration from a string.
pub fn parse_config_str(s: &str) -> Result<HashMap<String, String>> {
    // Pattern supports either a quoted value (captures group 2, can include '#')
    // or an unquoted value (captures group 3, stops at whitespace or '#').
    // Example matches:
    //   KEY = "value # not a comment"   -> group2 = value # not a comment
    //   KEY = value                      -> group3 = value
    let re = Regex::new(r##"^\s*([A-Za-z0-9_]+)\s*=\s*(?:"([^"]*)"|([^#\s]+))\s*(?:#.*)?$"##).unwrap();
    let mut map = HashMap::new();
    for line in s.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') { continue; }
        if let Some(cap) = re.captures(t) {
            let key = cap.get(1).unwrap().as_str().to_string();
            let val = if let Some(v) = cap.get(2) {
                v.as_str().to_string()
            } else if let Some(v) = cap.get(3) {
                v.as_str().to_string()
            } else {
                String::new()
            };
            map.insert(key, val);
        } else {
            // Non-matching non-comment lines are ignored to be permissive
            // of commented-out or legacy formats that don't follow key=value.
            continue;
        }
    }
    Ok(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_basic() {
        let input = r#"
            # comment
            UI_PORT = "8080" # trailing
            LF_QHTLFIREWALL = 1
        "#;
        let m = parse_config_str(input).unwrap();
        assert_eq!(m.get("UI_PORT").unwrap(), "8080");
        assert_eq!(m.get("LF_QHTLFIREWALL").unwrap(), "1");
    }
}

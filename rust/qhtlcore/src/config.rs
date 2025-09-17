use anyhow::{bail, Context, Result};
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
    let re = Regex::new(r#"^\s*([A-Za-z0-9_]+)\s*=\s*\"?([^\"#]*)\"?\s*(?:#.*)?$"#).unwrap();
    let mut map = HashMap::new();
    for (idx, line) in s.lines().enumerate() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') { continue; }
        if let Some(cap) = re.captures(t) {
            let key = cap.get(1).unwrap().as_str().to_string();
            let mut val = cap.get(2).unwrap().as_str().trim().to_string();
            // Unescape common sequences
            val = val.replace("\\\"", "\"");
            map.insert(key, val);
        } else {
            // Non-matching non-comment lines are considered format errors
            bail!("invalid config line {}: {}", idx + 1, line);
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

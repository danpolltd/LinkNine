use qhtlcore::config::parse_config_str;

#[test]
fn parses_realistic_subset() {
    let input = r#"
        # Minimal realistic sample
        LF_DAEMON = 1
        UI_PORT = "2087" # default
        THIS_UI = qhtlmanager
        LF_QHTLFIREWALL = 1
        IGNORE_FILE = "/etc/qhtlfirewall/qhtlfirewall.ignore"
        SPECIAL = "value # not a comment"

        # invalid or legacy lines should be ignored, not error
        not_a_key this is ignored
        SOME LIST = [1,2,3]
    "#;

    let m = parse_config_str(input).expect("parse");
    assert_eq!(m.get("LF_DAEMON").map(String::as_str), Some("1"));
    assert_eq!(m.get("UI_PORT").map(String::as_str), Some("2087"));
    assert_eq!(m.get("THIS_UI").map(String::as_str), Some("qhtlmanager"));
    assert_eq!(m.get("LF_QHTLFIREWALL").map(String::as_str), Some("1"));
    assert_eq!(m.get("IGNORE_FILE").map(String::as_str), Some("/etc/qhtlfirewall/qhtlfirewall.ignore"));
    assert_eq!(m.get("SPECIAL").map(String::as_str), Some("value # not a comment"));
}

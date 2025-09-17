use qhtlcore::net::get_interfaces;

#[test]
fn lists_interfaces() {
    let ifs = get_interfaces().expect("get interfaces");
    // On most systems at least loopback exists. Don't assert non-empty in CI containers,
    // just ensure call succeeds and names are unique.
    let mut dedup = ifs.clone();
    dedup.sort();
    dedup.dedup();
    assert_eq!(ifs, dedup);
}

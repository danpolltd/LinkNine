use anyhow::Result;
use std::collections::BTreeSet;

/// Return a sorted list of network interface names available on the host.
/// Loopback (lo) is included; duplicates are removed.
pub fn get_interfaces() -> Result<Vec<String>> {
    let mut names = BTreeSet::new();
    for iface in get_if_addrs::get_if_addrs()? {
        names.insert(iface.name);
    }
    Ok(names.into_iter().collect())
}

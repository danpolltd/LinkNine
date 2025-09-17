use anyhow::Result;
use std::net::{Ipv4Addr, Ipv6Addr};

/// Check an IP or CIDR string. Returns Ok(Some(4)) for IPv4, Ok(Some(6)) for IPv6,
/// Ok(None) for invalid/not allowed per Perl semantics.
/// If `ip_inout` is provided, it will be normalized (IPv6 shortened) and CIDR kept.
pub fn check_ip(ip_inout: Option<&mut String>, input: &str) -> Result<Option<u8>> {
    check_ip_impl(ip_inout, input, false)
}

/// Like check_ip but enforces IPv4 PUBLIC only (no private/reserved) similar to cccheckip.
pub fn cc_check_ip(ip_inout: Option<&mut String>, input: &str) -> Result<Option<u8>> {
    check_ip_impl(ip_inout, input, true)
}

fn check_ip_impl(mut ip_inout: Option<&mut String>, input: &str, cc_public_v4: bool) -> Result<Option<u8>> {
    let (ip_str, cidr_opt) = split_cidr(input);
    if let Some(c) = cidr_opt {
        if !c.chars().all(|ch| ch.is_ascii_digit()) { return Ok(None); }
    }

    // Try IPv4
    if let Ok(ip) = ip_str.parse::<Ipv4Addr>() {
        if ip == Ipv4Addr::LOCALHOST { return Ok(None); }
        if let Some(c) = cidr_opt {
            let c: u8 = c.parse().unwrap_or(0);
            if c == 0 || c > 32 { return Ok(None); }
        }
        if cc_public_v4 && !is_public_ipv4(&ip) { return Ok(None); }
        if let Some(out) = ip_inout.as_deref_mut() {
            if let Some(c) = cidr_opt { *out = format!("{}/{}", ip, c); } else { *out = ip.to_string(); }
        }
        return Ok(Some(4));
    }

    // Try IPv6
    if let Ok(ip) = ip_str.parse::<Ipv6Addr>() {
        if let Some(c) = cidr_opt {
            let c: u8 = c.parse().unwrap_or(0);
            if c == 0 || c > 128 { return Ok(None); }
        }
        // Perl removed colons and leading zeros and compared == 1; that's ::1
        if ip.is_loopback() { return Ok(None); }

        // Normalize IPv6 using standard formatting (compressed)
        if let Some(out) = ip_inout {
            let s = ip.to_string();
            if let Some(c) = cidr_opt { *out = format!("{}/{}", s, c); } else { *out = s; }
        }
        return Ok(Some(6));
    }

    Ok(None)
}

fn split_cidr(s: &str) -> (&str, Option<&str>) {
    if let Some(pos) = s.find('/') { (&s[..pos], Some(&s[pos+1..])) } else { (s, None) }
}

fn is_public_ipv4(ip: &Ipv4Addr) -> bool {
    // Exclude private, loopback, link-local, broadcast, and reserved ranges.
    // 10.0.0.0/8
    if ip.octets()[0] == 10 { return false; }
    // 172.16.0.0/12
    if ip.octets()[0] == 172 && (16..=31).contains(&ip.octets()[1]) { return false; }
    // 192.168.0.0/16
    if ip.octets()[0] == 192 && ip.octets()[1] == 168 { return false; }
    // 169.254.0.0/16 (link-local)
    if ip.octets()[0] == 169 && ip.octets()[1] == 254 { return false; }
    // 0.0.0.0/8
    if ip.octets()[0] == 0 { return false; }
    // 127.0.0.0/8 (loopback)
    if ip.octets()[0] == 127 { return false; }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v4_basic() {
        assert_eq!(check_ip(None, "1.2.3.4").unwrap(), Some(4));
        assert_eq!(check_ip(None, "127.0.0.1").unwrap(), None);
        assert_eq!(check_ip(None, "1.2.3.4/33").unwrap(), None);
        assert_eq!(check_ip(None, "1.2.3.4/24").unwrap(), Some(4));
        let mut s = String::new();
        assert_eq!(check_ip(Some(&mut s), "8.8.8.8/24").unwrap(), Some(4));
        assert_eq!(s, "8.8.8.8/24");
    }

    #[test]
    fn v6_basic() {
        assert_eq!(check_ip(None, "2001:db8::1").unwrap(), Some(6));
        assert_eq!(check_ip(None, "::1").unwrap(), None);
        assert_eq!(check_ip(None, "2001:db8::1/0").unwrap(), None);
        assert_eq!(check_ip(None, "2001:db8::1/129").unwrap(), None);
        let mut s = String::new();
        assert_eq!(check_ip(Some(&mut s), "2001:0db8:0:0::1").unwrap(), Some(6));
        // normalized compression
        assert_eq!(s, "2001:db8::1");
    }

    #[test]
    fn cc_public_v4() {
        assert_eq!(cc_check_ip(None, "8.8.8.8").unwrap(), Some(4));
        assert_eq!(cc_check_ip(None, "10.1.2.3").unwrap(), None);
        assert_eq!(cc_check_ip(None, "192.168.1.1").unwrap(), None);
        assert_eq!(cc_check_ip(None, "169.254.1.1").unwrap(), None);
    }
}

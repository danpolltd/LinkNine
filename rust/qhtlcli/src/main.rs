use anyhow::Result;
use qhtlcore::{config::parse_config_file, net::get_interfaces};
use std::env;

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    let mut show_if = true;
    let mut show_cfg = false;
    let mut cfg_path: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--list-interfaces" => show_if = true,
            "--no-list-interfaces" => show_if = false,
            "--config" => {
                if i + 1 < args.len() { cfg_path = Some(args[i + 1].clone()); i += 1; }
            }
            "--dump-config" => show_cfg = true,
            _ => {}
        }
        i += 1;
    }

    if show_if {
        let ifs = get_interfaces()?;
        for name in ifs { println!("{}", name); }
    }

    if show_cfg {
        let path = cfg_path.unwrap_or_else(|| "/etc/qhtlfirewall/qhtlfirewall.conf".to_string());
        match parse_config_file(&path) {
            Ok(map) => {
                let mut keys: Vec<_> = map.keys().collect();
                keys.sort();
                for k in keys { println!("{}={}", k, map[k]); }
            }
            Err(err) => {
                eprintln!("failed to parse {}: {}", path, err);
            }
        }
    }

    Ok(())
}

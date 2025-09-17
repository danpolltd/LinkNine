# Rust port (WIP)

This directory contains an incremental Rust port of selected qhtlfirewall components.

- qhtlcore: core library (network helpers, config parsing)
- qhtlcli: tiny CLI to exercise the core

Build (optional):
- Install Rust (https://rustup.rs)
- From this directory, run `cargo build --release`

Usage examples:
- `cargo run -p qhtlcli -- --list-interfaces`
- `cargo run -p qhtlcli -- --dump-config --config /etc/qhtlfirewall/qhtlfirewall.conf`

Notes:
- Parser supports KEY = "value" or KEY = value with trailing comments.
- Interface listing uses get_if_addrs; results are unique and sorted.

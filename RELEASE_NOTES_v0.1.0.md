v0.1.0

What’s new
- Initial public release
- Main-only workflow (no branches)
- Systemd alignment: qhtlwaterfall (service), qhtlfirewall (oneshot)
- Perl modules compile clean; fixes across core modules
- Cloudflare integration is optional and safe when LWP::UserAgent isn’t present

Install/Update (one-liner)
Optional for CloudLinux/CentOS:

curl -fsSL https://codeload.github.com/danpolltd/LinkNine/tar.gz/refs/heads/main | tar -xz -C /tmp && bash /tmp/LinkNine-main/qhtlfirewall/install.sh

Notes
- README intentionally empty for this release
- Internal parity tooling removed from repository
- _upstream_scripts excluded from release/source archives

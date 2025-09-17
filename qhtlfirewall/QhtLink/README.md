QhtLink Perl Modules

These modules make up the internal library for QhtLink Firewall.

- Namespace: All internal modules are under `QhtLink::*`.
- External integrations: qhtlwatcher integration is provided under `QhtLink::qhtlwatcher` and `QhtLink::qhtlwatcherUI`.

Modules overview (non-exhaustive):
- QhtLink::Config — configuration loader and accessors
- QhtLink::Service — service management for qhtlwaterfall
- QhtLink::Slurp — safe file slurping utilities
- QhtLink::URLGet — HTTP download helper with fallback to curl/wget
- QhtLink::DisplayUI / DisplayResellerUI — WHM/UI renderers
- QhtLink::cseUI — simplified file explorer used by panels

Conventions:
- Use `use lib '/usr/local/qhtlfirewall/lib';` to locate installed libs on target systems.
- Keep user-agent for network calls as `QHTL`.
- All modules must use the `QhtLink::*` namespace; legacy names are not used.

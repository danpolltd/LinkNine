# Parity Sweep Report

This document tracks a line-by-line parity check between upstream ConfigServer modules and rebranded QhtLink modules. The helper script `tools/parity_diff.sh` normalizes common rename tokens and prints unified diffs to focus on logic changes.

## How to run

```bash
bash tools/parity_diff.sh | less -R
```

## Status summary

- RegexMain.pm — fixed and aligned (top-of-file init, Apache ERRPORT detect, pslinecheck scope). Commit(s): 119f608, c9add5c.
- qhtlmanagerUI.pm — syntax/path cleanups (semicolon, // collapse). Commit: 5a8f8e6.
- CloudFlare.pm — lazy-load LWP::UserAgent; logs and no-ops if missing. Commit: 5a8f8e6.

## Items to review next

1. DisplayUI.pm vs upstream UI: verify form names, action routes, and rebrand labels.
2. Service.pm: ensure all service names use qhtlwaterfall/qhtlfirewall consistently.
3. URLGet.pm: confirm URLGET gating matches upstream semantics.
4. Logger.pm: ensure log paths and rotation notes match expected install paths.
5. Any remaining literal paths under /etc/csf → /etc/qhtlfirewall.

## Notes

- The diff is advisory: upstream and local may have intentional changes beyond rebrand (e.g., Apache ERRPORT auto-detect defaults). Record each intentional divergence here with rationale.

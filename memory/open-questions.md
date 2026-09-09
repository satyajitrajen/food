# Open Questions

| # | Question | Blocking | Owner | Status |
|---|----------|----------|-------|--------|
| Q-1 | Split-tender in v1 payment UI or Phase 3? (PRD FR-P1 says later) | P2.4 design | Satyajit | deferred P3 |
| Q-2 | Do staff PINs hash server-side while demo login stays local? (needs offline auth policy) | P1.3 | Satyajit | resolved for v1: server-first login; offline terminals fall back to the local seeded demo staff only (real offline PIN verify would need a client PIN vault — see phase report) |
| Q-3 | Invoice number scope: per-outlet daily reset vs continuous? | P2.4 | Satyajit | open (default: continuous per outlet) |
| Q-4 | Printers: which ESC/POS models must P5 support? | P5 | Satyajit | interface shipped (PrinterAdapter + raw-9100); hardware validation pending models |
| Q-5 | SSE drop policy: hub drops events for slow consumers; terminals self-heal via hydrate on reconnect — is a Last-Event-ID resume stream needed for pilot scale? | P5 hardening | Satyajit | open |

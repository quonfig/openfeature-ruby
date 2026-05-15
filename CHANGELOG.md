# Changelog

## 0.0.7 - 2026-05-15

- **Chore: bump `quonfig` runtime floor to `>= 0.0.16` (qfg-35sm + four post-review hardening fixes).** The 0.0.16 release of the native Ruby SDK replaces `ld-eventsource` entirely with an SDK-owned SSE reconnect loop and lands four post-review hardening fixes: `Thread#raise` containment via `handle_interrupt` (qfg-tj18), `on_envelope` callback isolation so a buggy listener can't cause reconnect storms (qfg-m3lk), 401/403/404 terminal-error classification so bad SDK keys stop hammering api-delivery-sse (qfg-i5xv), and a `Process._fork` hook so SSE auto-restarts in Puma/Unicorn workers without manual `on_worker_boot` wiring (qfg-ryov). Provider code is unchanged — all four improvements live in the SDK's SSE delivery path and fork lifecycle. Tightening the floor signals this provider is tested against and requires the production-hardened SDK.

## 0.0.6 - 2026-05-15

- **Chore: bump `quonfig` runtime floor to `>= 0.0.15` (qfg-ie49).** The 0.0.15 release of the native Ruby SDK fixes how `restart_total` (Layer 1 SSE) is counted under clean-FIN reconnects and hardens the reconnect-counting logger wrapper against worker-thread death. Provider code is unchanged — the fix is in the SDK's SSE delivery path. Tightening the floor signals this provider is tested against and requires the fixed SDK so downstream installs of the OpenFeature provider can't pull in an SSE-restart-buggy SDK.

## 0.0.5 - 2026-05-07

- **Chore: bump `quonfig` runtime floor to `>= 0.0.13` (qfg-7jnb.11).** The 0.0.13 release of the native Ruby SDK adds support for the `IS_PRESENT` and `IS_NOT_PRESENT` targeting operators (qfg-7jnb.6). Tightening the floor signals that this provider is tested against and requires the new SDK; downstream Bundler resolutions already on `>= 0.0.12` would have picked up 0.0.13 automatically, but the explicit floor prevents a stale install from masking missing-operator behaviour.

# Changelog

## 1.0.1 - 2026-09-11

- Raise the `quonfig` dependency floor from `>= 1.0.0` to `>= 1.4.0` so provider users inherit
  the fork-safety fix (qfg-lv4n.1, qfg-4t5o). On quonfig 1.0.0-1.3.0 a process that forked and
  kept evaluating in the parent went permanently dark after the fork while `connection_state`
  reported `:connected`; 1.4.0 leaves the parent untouched and re-initializes the child on its
  first use. No change to this provider's own behavior.

## 1.0.0 - 2026-06-06

- **Stable 1.0.0 release.** The Quonfig OpenFeature provider for Ruby is now declared
  stable and depends on the `quonfig` gem >= 1.0.0. No API or behavior changes from
  0.0.10 — this is a coordinated 1.0.0 version stamp across the entire Quonfig SDK
  family.

## 0.0.10 - 2026-06-02

- Raise the `quonfig` dependency floor from `>= 0.0.19` to `>= 0.0.21` to inherit dev-context injection default-on (qfg-bw7g.9, via qfg-bw7g.5). No change to this provider's behavior — dev-context lives below the OpenFeature layer, so OpenFeature users now get `quonfig-user.email` injection by default in local dev (gated on the `qfg login` token file; inert in production).

## 0.0.9 - 2026-05-28

- **Chore: bump `quonfig` runtime floor to `>= 0.0.19` (sdk-1.0-unification).** The 0.0.19 release of the native Ruby SDK lands as part of the cross-SDK 1.0 unification effort. Provider code is unchanged — the improvements live in the SDK itself. Tightening the floor signals this provider is tested against and requires the unified SDK so downstream installs of the OpenFeature provider pull in the matching SDK release.

## 0.0.8 - 2026-05-21

- **Chore: bump `quonfig` runtime floor to `>= 0.0.18` (qfg-35sm follow-up).** The 0.0.17 and 0.0.18 releases of the native Ruby SDK land datadir and SSE improvements: opt-in `data_dir_auto_reload` with fork-safe watcher restart (qfg-mol-2da), int/double config-value coercion to real JSON numbers at datadir load time so the loaded envelope matches what api-delivery emits over HTTP/SSE (qfg-38sf.8), and an SSE `Net#read_timeout` headroom fix so the watchdog deadline always fires before the stdlib timeout and the SDK surfaces `SSEReadDeadlineExceeded` rather than a raw `Net::ReadTimeout` (qfg-6y44). Provider code is unchanged — all the improvements live in the SDK's datadir loader and SSE delivery path. Tightening the floor signals this provider is tested against and requires the production-hardened SDK so downstream installs of the OpenFeature provider can't pull in an SDK missing the datadir numeric-coercion fix.

## 0.0.7 - 2026-05-15

- **Chore: bump `quonfig` runtime floor to `>= 0.0.16` (qfg-35sm + four post-review hardening fixes).** The 0.0.16 release of the native Ruby SDK replaces `ld-eventsource` entirely with an SDK-owned SSE reconnect loop and lands four post-review hardening fixes: `Thread#raise` containment via `handle_interrupt` (qfg-tj18), `on_envelope` callback isolation so a buggy listener can't cause reconnect storms (qfg-m3lk), 401/403/404 terminal-error classification so bad SDK keys stop hammering api-delivery-sse (qfg-i5xv), and a `Process._fork` hook so SSE auto-restarts in Puma/Unicorn workers without manual `on_worker_boot` wiring (qfg-ryov). Provider code is unchanged — all four improvements live in the SDK's SSE delivery path and fork lifecycle. Tightening the floor signals this provider is tested against and requires the production-hardened SDK.

## 0.0.6 - 2026-05-15

- **Chore: bump `quonfig` runtime floor to `>= 0.0.15` (qfg-ie49).** The 0.0.15 release of the native Ruby SDK fixes how `restart_total` (Layer 1 SSE) is counted under clean-FIN reconnects and hardens the reconnect-counting logger wrapper against worker-thread death. Provider code is unchanged — the fix is in the SDK's SSE delivery path. Tightening the floor signals this provider is tested against and requires the fixed SDK so downstream installs of the OpenFeature provider can't pull in an SSE-restart-buggy SDK.

## 0.0.5 - 2026-05-07

- **Chore: bump `quonfig` runtime floor to `>= 0.0.13` (qfg-7jnb.11).** The 0.0.13 release of the native Ruby SDK adds support for the `IS_PRESENT` and `IS_NOT_PRESENT` targeting operators (qfg-7jnb.6). Tightening the floor signals that this provider is tested against and requires the new SDK; downstream Bundler resolutions already on `>= 0.0.12` would have picked up 0.0.13 automatically, but the explicit floor prevents a stale install from masking missing-operator behaviour.

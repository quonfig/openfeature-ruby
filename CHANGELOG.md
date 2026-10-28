# Changelog

## 2.1.0 - 2026-10-28

A malformed value now resolves with error code `PARSE_ERROR` instead of `TYPE_MISMATCH`
(qfg-9xsl, mirrors integration-test-data `tests/openfeature/openfeature.yaml` Case 6). You still
get your default with reason `ERROR`. This covers a value of a type the `fetch_*` method reads that
does not parse:

- a stored int `"twelve"` or double `"abc"`;
- an int or double provided by an ENV_VAR set to an unparseable string, such as `"twelve"`;
- a malformed stored duration such as `"30s"`, read with `fetch_string_value`.

A read with the method for another type (an int config read with `fetch_boolean_value`) stays
`TYPE_MISMATCH`, as does a number that parses but does not convert exactly (`fetch_integer_value`
on `3.9`). sdk-ruby's `*_details` report both cases as `TYPE_MISMATCH`, so the provider tells them
apart: on a `TYPE_MISMATCH` it checks the config's stored `valueType` and, if the method can read
that type, reads it with the native getter for that type. If that read fails too, the value is
malformed. This extra read happens only on the error path.

If you alert or branch on `TYPE_MISMATCH` for bad config data, match `PARSE_ERROR` as well.

## 2.0.0 - 2026-10-27

**BREAKING / UPGRADE (major, qfg-zvyy.6).** This release tracks sdk-ruby 2.0.0, the cross-SDK
typed-getter contract. Require `quonfig` (sdk-ruby) `>= 2.0.0` (floor raised from `>= 1.11.0`). No
change to this provider's code: it passes through the SDK's `*_details` results, so provider users
inherit the contract below.

### UPGRADE to 2.0

A value a `fetch_*` method cannot read as its type returns your default with reason `ERROR` and
error code `TYPE_MISMATCH`. Strings are never coerced, and the only number conversions are exact
ones. What changes for provider users:

- `fetch_float_value` on an int config now returns the value (`30` -> `30.0`). 1.x returned your
  default with `TYPE_MISMATCH`.
- `fetch_integer_value` on a double config returns the value when it is whole and within
  +/-(2^53-1) (`3.0` -> `3`). 1.x returned your default for every double. `3.9`, `2^53` and `1e300`
  still return your default with `TYPE_MISMATCH`, never truncated.
- `fetch_number_value` on a `duration` config returns your default with `TYPE_MISMATCH`. 1.x
  returned the duration in milliseconds (`30000`, reason `STATIC`). Durations are native-only: use
  `provider.client.get_duration` (integer milliseconds). `fetch_float_value` on a duration already
  returned your default.
- A malformed stored int or double (for example `"twelve"`) or a malformed ENV_VAR value returns
  your default with error code `TYPE_MISMATCH`, as in sdk-go. 1.x reported `GENERAL`. An unset
  ENV_VAR still returns your default with `GENERAL`.
- sdk-ruby logs one WARN per key per client when a read returns your default because of a type
  mismatch, a malformed value, an unset ENV_VAR or a decryption failure. The line names the key and
  types, never the value. A wrong decryption key now degrades to your defaults with these WARNs.
- If you call the native client via `provider.client`: typed getters with a `default:` return the
  default instead of raising, `enabled?` is true only for the bool `true` and never raises, and
  `get_bool` on a stored string `"true"` is a type mismatch. See the sdk-ruby CHANGELOG
  "UPGRADE to 2.0".

These already held under 1.11.0 through the provider, and the new tests now pin them: a stored
string `"true"` / `"false"` read as a boolean, a stored `"3"` read as a number, an int or bool read as
a string, an int read as a boolean, and a string or bool read as an object all return your default
with `TYPE_MISMATCH`.

### Tests

- New `test/integration/test_typed_getter_contract.rb` (31 tests) drives the real provider through
  the OpenFeature client against the integration-test-data `getter.contract.*` fixtures. 7 of the 31
  fail on sdk-ruby 1.11.0; all pass on 2.0.0.

## 1.1.0 - 2026-10-23

- **UPGRADE: raise the `quonfig` floor from `>= 1.10.0` to `>= 1.11.0`. Requires sdk-ruby 1.11.0:
  SSE event and config body size caps, `Client#callback_errors_total`.** The provider code does not
  change for 1.11.0. The new floor means every install of this provider gets those sdk-ruby changes:
  an oversized SSE event (over 4 MiB) or config body (over 16 MiB) is treated as a failed attempt
  instead of being read without limit, and `Dir.home` failures no longer raise from `Client.new`.
  Read the 1.11.0 entry in the sdk-ruby CHANGELOG. Build and test against `quonfig` 1.11.0
  (Gemfile.lock).
- **UPGRADE: raise the `quonfig` floor from `>= 1.7.2` to `>= 1.10.0` (qfg-9p4i.12).** The provider
  now uses sdk-ruby 1.10.0's init-failure surface (`on_init_failure: :fail | :wait | :continue`,
  `init_timeout_ms`, `Client#ready?` / `#wait_for_ready`, `Quonfig::Errors::InitializationError`).
  Read the 1.10.0 entry in the sdk-ruby CHANGELOG: `Client.new` now retries a failed boot until
  `init_timeout_ms` (default 10s) before it raises, instead of raising on the first failed attempt.
- **Added (minor): the provider emits OpenFeature events and its status follows `on_init_failure`
  (init-failure design B.5).** Pass `on_init_failure:` and `init_timeout_ms:` to `Provider.new`; they
  are forwarded to `Quonfig::Client.new` as before.
  - `:fail` (the default): `init` raises `Quonfig::Errors::InitializationError` when no config loads,
    so `set_provider_and_wait` raises and the provider is ERROR. sdk-ruby returns no client under
    `:fail`, so nothing retries in the background; the process restart is the retry.
  - `:wait`: `init` blocks until config loads. The provider is NOT_READY for the whole wait, then READY.
  - `:continue` with no config: `init` resolves, then the provider emits `PROVIDER_ERROR` (error code
    `PROVIDER_NOT_READY`), so its status is ERROR rather than READY while every evaluation returns the
    code default. When the client's background retry loads config, the provider emits
    `PROVIDER_READY`. Before, the provider reported READY and emitted no events.
  - A client injected with `client:` gets the same treatment: if it has no config at `init`, the
    provider reports ERROR until it heals.
- **Fix: an evaluation before config loads reports `PROVIDER_NOT_READY`.** sdk-ruby 1.10.0's
  `*_details` getters return error code `PROVIDER_NOT_READY` on a client with no config; the provider
  mapped that to `GENERAL`. `Quonfig::Errors::InitializationError` (any reason, not only the timeout
  subclass) now maps to `PROVIDER_NOT_READY` too.

## 1.0.3 - 2026-10-16

- Build and test against `quonfig` 1.8.0 (Gemfile.lock). The runtime floor stays at `>= 1.7.2`: this
  provider does not read `terminal_failure?` or `connection_state`, so nothing in it depends on
  1.8.0. A fresh `bundle install` / `bundle update quonfig` resolves to 1.8.0, which changes behavior
  OpenFeature users see through this provider:
  - **UPGRADE: rule operators follow one cross-SDK semantics (qfg-goi1.5.7).** Pass dates in the
    evaluation context as epoch milliseconds or ISO 8601 / RFC3339 with `Z` or a numeric offset.
    Date-only, offset-less and free-form date strings no longer parse, so those `PROP_BEFORE` /
    `PROP_AFTER` criteria stop matching. Whole-number floats read as plain digits (`1234567.0` ->
    `"1234567"`) in string operators, and `PROP_SEMVER_*` accepts abbreviated versions (`"4.1"`).
  - **UPGRADE: a rejected SDK key no longer latches the client off (qfg-goi1.10.26).** A
    401/403/404/410 poll cycle enters an auth-failed state that probes every 150-300 s and recovers
    by itself when the key works again, logging one ERROR (status and host, never the key) instead
    of stopping the stream for the life of the process.
  - Object flags (`fetch_object_value`) now get a fresh copy of the JSON value on every call, so a
    caller mutating a resolved Hash or Array no longer changes later resolutions (qfg-goi1.10.3).
  - Fixes: weighted-rollout `confidential` / `decryptWith` variants are redacted in telemetry
    (qfg-goi1.2.39), `EnvVarParseError` messages use the cross-SDK wording (qfg-goi1.10.21), and
    install/SSE robustness fixes (qfg-goi1.10.2, qfg-goi1.2.35).

## 1.0.2 - 2026-10-09

- Raise the `quonfig` dependency floor from `>= 1.4.0` to `>= 1.7.2` so provider users inherit
  sdk-ruby 1.7.2: no secret values in `TypeMismatchError` / `EnvVarParseError`, UTF-8 datadir
  reads, `SemanticLoggerFilter` never raises, init race and regex match timeout fixes
  (qfg-goi1.2.11, qfg-xy92, qfg-goi1.1.3, qfg-goi1.2.21). No change to this provider's behavior.

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

# quonfig-openfeature

OpenFeature provider for [Quonfig](https://quonfig.com) -- Ruby server-side SDK.

This gem wraps the `quonfig` native Ruby SDK and implements the
[OpenFeature](https://openfeature.dev) `OpenFeature::SDK::Provider` contract.

## Install

```bash
gem install quonfig-openfeature openfeature-sdk quonfig
```

Or with Bundler:

```ruby
gem 'quonfig-openfeature'
gem 'openfeature-sdk'
gem 'quonfig'
```

## Usage

```ruby
require 'quonfig/openfeature'
require 'open_feature/sdk'

provider = Quonfig::OpenFeature::Provider.new(
  sdk_key: 'qf_sk_production_...'
  # targeting_key_mapping: 'user.id', # default
)

OpenFeature::SDK.set_provider_and_wait(provider)

client = OpenFeature::SDK.build_client

# Boolean flag
enabled = client.fetch_boolean_value(flag_key: 'my-feature', default_value: false)

# String config
welcome = client.fetch_string_value(flag_key: 'welcome-message', default_value: 'Hello!')

# Number config (Integer or Float)
timeout = client.fetch_number_value(flag_key: 'request-timeout-ms', default_value: 5000)

# Object config (JSON or string_list)
allowed_plans = client.fetch_object_value(flag_key: 'allowed-plans', default_value: [])

# With evaluation context (per-request)
ctx = OpenFeature::SDK::EvaluationContext.new(
  targeting_key: 'user-123',  # maps to user.id by default
  'user.plan'   => 'pro',
  'org.tier'    => 'enterprise'
)
is_pro = client.fetch_boolean_value(flag_key: 'pro-feature', default_value: false,
                                     evaluation_context: ctx)
```

## Startup failure and provider status

The provider forwards `on_init_failure:` and `init_timeout_ms:` to `Quonfig::Client.new`, and its
OpenFeature status follows the mode:

| `on_init_failure` | `init` when no config loads | Provider status | Later |
|-------------------|-----------------------------|-----------------|-------|
| `:fail` (default) | raises `Quonfig::Errors::InitializationError` after `init_timeout_ms` (at once if the SDK key is rejected) | ERROR | No client exists, so nothing retries; restart the process |
| `:wait`           | blocks and retries with no upper bound | NOT_READY while waiting | READY when config loads |
| `:continue`       | returns; emits `PROVIDER_ERROR` | ERROR; evaluations return your default with `PROVIDER_NOT_READY` | emits `PROVIDER_READY` when the background retry loads config |

```ruby
provider = Quonfig::OpenFeature::Provider.new(
  sdk_key: 'qf_sk_production_...',
  on_init_failure: :continue, # :fail (default), :wait or :continue
  init_timeout_ms: 10_000
)
OpenFeature::SDK.set_provider_and_wait(provider)
```

## Context mapping

OpenFeature context is flat; Quonfig context is nested by namespace. This provider
maps between them using dot-notation:

| OpenFeature context key | Quonfig namespace | Quonfig property |
|-------------------------|-------------------|------------------|
| `targeting_key`         | `user`            | `id` (configurable via `targeting_key_mapping`) |
| `"user.email"`          | `user`            | `email`          |
| `"org.tier"`            | `org`             | `tier`           |
| `"country"` (no dot)    | `""` (default)    | `country`        |
| `"user.ip.address"`     | `user`            | `ip.address` (first dot only) |

### Customising `targeting_key` mapping

```ruby
provider = Quonfig::OpenFeature::Provider.new(
  sdk_key: 'qf_sk_...',
  targeting_key_mapping: 'account.id' # maps targeting_key to { account: { id: ... } }
)
```

## Accessing native SDK features

The `client` reader returns the underlying `Quonfig::Client` for features not
available through the OpenFeature API. Extra keyword arguments to `Provider.new`
are forwarded to `Quonfig::Client.new`, so pass `logger_key:` there to use
`should_log?(logger_path:)` (without it, `should_log?` raises `Quonfig::Error`):

```ruby
provider = Quonfig::OpenFeature::Provider.new(
  sdk_key: 'qf_sk_production_...',
  logger_key: 'log-level.my-app' # the log-level config should_log? evaluates
)
OpenFeature::SDK.set_provider_and_wait(provider)

native = provider.client

# Log level integration (requires logger_key above)
native.should_log?(logger_path: 'auth', desired_level: :debug,
                   contexts: { 'user' => { 'id' => 'user-123' } })

# List all config keys
keys = native.keys

# Per-request bound client
native.with_context('user' => { 'plan' => 'pro' }) do |bound|
  bound.get_bool('pro-feature')
end
```

## What you lose vs. the native SDK

OpenFeature is designed for feature flags, not general configuration. Some
Quonfig features require the native `quonfig` SDK:

1. **Log levels** -- `should_log?` and the `semantic_logger_filter` are native-only.
2. **`string_list` configs** -- accessed via `fetch_object_value` and used as `Array<String>`.
3. **`duration` configs** -- `fetch_string_value` returns the stored ISO 8601 text unchanged
   (`"PT90S"`). For integer milliseconds use `provider.client.get_duration`. `fetch_float_value`
   and `fetch_number_value` on a duration config return your default with `TYPE_MISMATCH`.
4. **`bytes` configs** -- not accessible via OpenFeature (no binary type in OF).
5. **`keys` / raw config inspection** -- native-only via `provider.client`.
6. **Context keys use dot-notation** -- `"user.email"`, not nested hashes.
7. **`targeting_key` maps to `user.id` by default** -- configure
   `targeting_key_mapping` if you target a different namespace.

## Typed reads

Each `fetch_*` method reads only values of its type (the cross-SDK typed-getter contract,
`quonfig` >= 2.0.0). A value of another type returns your default with reason `ERROR` and error
code `TYPE_MISMATCH`:

- A stored string is never coerced: `"false"` is not a boolean and `"3"` is not a number.
- Numbers convert only when exact: `fetch_float_value` on an int config returns `30.0`, and
  `fetch_integer_value` on a double config returns the value only when it is whole and within
  +/-(2^53-1) (`3.0` -> `3`; `3.9` is a mismatch, never truncated).
- A malformed value of a type the method reads returns your default with `PARSE_ERROR`: a stored
  int `"twelve"`, an int or double ENV_VAR set to `"twelve"`, or a stored duration `"30s"` read
  with `fetch_string_value`. A read with the method for another type stays `TYPE_MISMATCH`. An
  unset ENV_VAR returns your default with `GENERAL`.

sdk-ruby logs one WARN per key when a read returns your default for one of these reasons.

## Offline / test mode

Pass `datadir:` to evaluate against a Quonfig workspace on disk -- the same
layout the integration test suite uses. No network or SDK key is required.

```ruby
provider = Quonfig::OpenFeature::Provider.new(
  datadir:     '/path/to/workspace',
  environment: 'Production',
  enable_sse:  false
)
```

## Development

```bash
bundle install
bundle exec rake test
```

The development `Gemfile` references the sibling `../sdk-ruby/` checkout via a
`path:` reference; downstream consumers depend on the `quonfig` gem from
RubyGems.

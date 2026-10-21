# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'socket'

# Provider status across the SDK's on_init_failure modes (init-failure design
# B.5, qfg-9p4i.12). Each test drives its own OpenFeature::SDK::Configuration so
# no global provider state leaks between tests.
class TestInitFailure < Minitest::Test
  Provider      = Quonfig::OpenFeature::Provider
  Reason        = ::OpenFeature::SDK::Provider::Reason
  ErrorCode     = ::OpenFeature::SDK::Provider::ErrorCode
  ProviderEvent = ::OpenFeature::SDK::ProviderEvent
  ProviderState = ::OpenFeature::SDK::ProviderState

  REFUSED = ['http://127.0.0.1:1'].freeze

  CONFIG = {
    'id' => '1', 'key' => 'heal.flag', 'type' => 'feature_flag', 'valueType' => 'bool',
    'sendToClientSdk' => false,
    'default' => {
      'rules' => [{ 'criteria' => [{ 'operator' => 'ALWAYS_TRUE' }], 'value' => { 'type' => 'bool', 'value' => true } }]
    }
  }.freeze

  def setup
    @config = ::OpenFeature::SDK::Configuration.new
    @events = Queue.new
    ProviderEvent::ALL_EVENTS.each do |type|
      @config.add_handler(type, ->(details) { @events << [type, details] })
    end
    @providers = []
    @servers = []
  end

  def teardown
    @providers.each(&:shutdown)
    @servers.each(&:close)
  end

  def network_provider(api_urls:, **opts)
    p = Provider.new(sdk_key: 'test-sdk-key', api_urls: api_urls, enable_sse: false,
                     collect_sync_interval: 3600, init_timeout_ms: 200, **opts)
    @providers << p
    p
  end

  def state(provider)
    # provider_state is private in openfeature-sdk 0.5.x, public in 0.6.x.
    @config.send(:provider_state, provider)
  end

  def wait_for_state(provider, expected, timeout: 10)
    deadline = Time.now + timeout
    sleep 0.02 until state(provider) == expected || Time.now > deadline
    assert_equal expected, state(provider)
  end

  def event_types
    types = []
    types << @events.pop[0] until @events.empty?
    types
  end

  # A delivery leg that answers 503 until +healthy_after+ seconds have passed,
  # then serves CONFIG. Stdlib-only so the provider gains no test dependency.
  def delivery_leg(healthy_after:)
    server = TCPServer.new('127.0.0.1', 0)
    @servers << server
    started = Time.now
    Thread.new do
      loop do
        sock = server.accept
        Thread.new(sock) do |s|
          while (line = s.gets) && line != "\r\n"; end
          if Time.now - started >= healthy_after
            body = JSON.generate('configs' => [CONFIG],
                                 'meta' => { 'version' => 'v1', 'environment' => 'dev', 'generation' => 1 })
            s.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                    "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
          else
            s.write("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
          end
          s.close
        rescue StandardError
          nil
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
    "http://127.0.0.1:#{server.addr[1]}"
  end

  # ---- fail -----------------------------------------------------------------

  # Decision 4: under :fail sdk-ruby raises from Client.new and returns no
  # client, so the provider is ERROR and evaluations are PROVIDER_NOT_READY.
  def test_fail_init_raises_and_provider_is_error
    p = network_provider(api_urls: REFUSED, on_init_failure: :fail)

    err = assert_raises(::OpenFeature::SDK::ProviderInitializationError) { @config.set_provider_and_wait(p) }
    assert_kind_of ::Quonfig::Errors::InitializationError, err.original_error
    assert_equal ProviderState::ERROR, state(p)
    assert_nil p.client

    details = p.fetch_boolean_value(flag_key: 'heal.flag', default_value: false)
    assert_equal Reason::ERROR, details.reason
    assert_equal ErrorCode::PROVIDER_NOT_READY, details.error_code
  end

  # ---- continue, no cache ---------------------------------------------------

  def test_continue_without_config_resolves_then_reports_error
    p = network_provider(api_urls: REFUSED, on_init_failure: :continue)

    @config.set_provider_and_wait(p) # resolves: :continue never raises

    wait_for_state(p, ProviderState::ERROR)
    assert_equal ProviderEvent::PROVIDER_ERROR, event_types.last

    details = p.fetch_boolean_value(flag_key: 'heal.flag', default_value: false)
    assert_equal false, details.value
    assert_equal Reason::ERROR, details.reason
    assert_equal ErrorCode::PROVIDER_NOT_READY, details.error_code
  end

  def test_continue_heals_and_emits_provider_ready
    leg = delivery_leg(healthy_after: 0.5)
    p = network_provider(api_urls: [leg], on_init_failure: :continue, fallback_poll_interval_ms: 200)

    @config.set_provider_and_wait(p)
    wait_for_state(p, ProviderState::ERROR)
    wait_for_state(p, ProviderState::READY)

    assert_equal [ProviderEvent::PROVIDER_READY, ProviderEvent::PROVIDER_ERROR, ProviderEvent::PROVIDER_READY],
                 event_types
    details = p.fetch_boolean_value(flag_key: 'heal.flag', default_value: false)
    assert_equal true, details.value
  end

  def test_shutdown_while_unhealed_emits_no_ready
    p = network_provider(api_urls: REFUSED, on_init_failure: :continue)
    @config.set_provider_and_wait(p)
    wait_for_state(p, ProviderState::ERROR)
    event_types

    p.shutdown
    sleep 0.2
    assert_empty event_types
  end

  # ---- healthy boots stay READY ----------------------------------------------

  def test_datadir_provider_is_ready_with_no_error_event
    p = build_provider
    @providers << p
    @config.set_provider_and_wait(p)
    sleep 0.1
    assert_equal ProviderState::READY, state(p)
    assert_equal [ProviderEvent::PROVIDER_READY], event_types
  end

  # ---- error code mapping -----------------------------------------------------

  def test_initialization_error_maps_to_provider_not_ready
    err = ::Quonfig::Errors::InitializationError.new('boom', reason: :unavailable)
    assert_equal ErrorCode::PROVIDER_NOT_READY, Quonfig::OpenFeature::Errors.to_error_code(err)
  end
end

# frozen_string_literal: true

require 'test_helper'

class TestContext < Minitest::Test
  Context = Quonfig::OpenFeature::Context

  def test_empty_context_returns_empty_hash
    assert_equal({}, Context.map_context(nil))
    assert_equal({}, Context.map_context({}))
    assert_equal({}, Context.map_context(::OpenFeature::SDK::EvaluationContext.new))
  end

  def test_targeting_key_maps_to_user_id_by_default
    ctx = ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'user-123')
    assert_equal({ 'user' => { 'id' => 'user-123' } }, Context.map_context(ctx))
  end

  def test_targeting_key_respects_custom_mapping
    ctx = ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'acct-1')
    assert_equal({ 'account' => { 'id' => 'acct-1' } },
                 Context.map_context(ctx, 'account.id'))
  end

  def test_targeting_key_with_no_dot_mapping_uses_empty_namespace
    ctx = ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'thing-1')
    assert_equal({ '' => { 'subject' => 'thing-1' } },
                 Context.map_context(ctx, 'subject'))
  end

  def test_dotted_key_splits_namespace_from_property
    ctx = ::OpenFeature::SDK::EvaluationContext.new('user.email' => 'a@example.com')
    assert_equal({ 'user' => { 'email' => 'a@example.com' } },
                 Context.map_context(ctx))
  end

  def test_undotted_key_lands_in_default_namespace
    ctx = ::OpenFeature::SDK::EvaluationContext.new(country: 'US')
    assert_equal({ '' => { 'country' => 'US' } }, Context.map_context(ctx))
  end

  def test_only_first_dot_is_a_separator
    ctx = ::OpenFeature::SDK::EvaluationContext.new('user.ip.address' => '1.2.3.4')
    assert_equal({ 'user' => { 'ip.address' => '1.2.3.4' } },
                 Context.map_context(ctx))
  end

  def test_nil_values_are_skipped
    ctx = ::OpenFeature::SDK::EvaluationContext.new('user.email' => nil,
                                                    'user.name' => 'Alice')
    assert_equal({ 'user' => { 'name' => 'Alice' } }, Context.map_context(ctx))
  end

  def test_combined_targeting_key_and_props
    ctx = ::OpenFeature::SDK::EvaluationContext.new(
      targeting_key: 'user-123',
      'user.email' => 'a@example.com',
      'org.tier' => 'enterprise',
      'country' => 'US'
    )
    expected = {
      'user' => { 'id' => 'user-123', 'email' => 'a@example.com' },
      'org' => { 'tier' => 'enterprise' },
      '' => { 'country' => 'US' }
    }
    assert_equal expected, Context.map_context(ctx)
  end

  def test_plain_hash_input_is_supported
    h = { 'user.email' => 'a@example.com', 'targeting_key' => 'u-1' }
    assert_equal(
      { 'user' => { 'id' => 'u-1', 'email' => 'a@example.com' } },
      Context.map_context(h)
    )
  end

  def test_camel_case_targeting_key_alias_is_handled
    h = { 'targetingKey' => 'u-2', 'org.tier' => 'pro' }
    assert_equal(
      { 'user' => { 'id' => 'u-2' }, 'org' => { 'tier' => 'pro' } },
      Context.map_context(h)
    )
  end
end

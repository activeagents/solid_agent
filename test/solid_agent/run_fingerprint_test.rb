# frozen_string_literal: true

require "test_helper"

# SolidAgent::RunFingerprint — stable instruction digests and their
# deterministic codenames, used to group runs into configuration cohorts.
class RunFingerprintTest < Minitest::Test
  def test_digest_is_stable_and_short
    a = SolidAgent::RunFingerprint.digest("You are a helpful agent.")
    b = SolidAgent::RunFingerprint.digest("You are a helpful agent.")

    assert_equal a, b
    assert_equal 8, a.length
    assert_match(/\A\h{8}\z/, a)
  end

  def test_digest_changes_with_instructions
    a = SolidAgent::RunFingerprint.digest("You are a helpful agent.")
    b = SolidAgent::RunFingerprint.digest("You are a rigorous agent.")

    refute_equal a, b
  end

  def test_digest_is_nil_for_blank_input
    assert_nil SolidAgent::RunFingerprint.digest(nil)
    assert_nil SolidAgent::RunFingerprint.digest("")
    assert_nil SolidAgent::RunFingerprint.digest("   ")
  end

  def test_codename_is_deterministic_adjective_noun
    digest = SolidAgent::RunFingerprint.digest("You are a helpful agent.")
    codename = SolidAgent::RunFingerprint.codename(digest)

    assert_equal codename, SolidAgent::RunFingerprint.codename(digest)
    adjective, noun = codename.split("-")
    assert_includes SolidAgent::RunFingerprint::ADJECTIVES, adjective
    assert_includes SolidAgent::RunFingerprint::NOUNS, noun
  end

  def test_codename_is_nil_without_digest
    assert_nil SolidAgent::RunFingerprint.codename(nil)
    assert_nil SolidAgent::RunFingerprint.codename("")
  end
end

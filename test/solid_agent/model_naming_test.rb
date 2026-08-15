# frozen_string_literal: true

require "test_helper"

class ModelNamingTest < Minitest::Test
  def test_strips_a_context_suffix
    assert_equal "Chat", SolidAgent::ModelNaming.base_for("ChatContext")
  end

  def test_strips_a_session_suffix
    assert_equal "Chat", SolidAgent::ModelNaming.base_for("ChatSession")
  end

  # Regression: chaining delete_suffix("Context").delete_suffix("Session")
  # reduced this to "" and produced a bare Message/Generation pair that
  # collided across every context in the app.
  def test_strips_at_most_one_suffix
    assert_equal "Session", SolidAgent::ModelNaming.base_for("SessionContext")
    assert_equal "Context", SolidAgent::ModelNaming.base_for("ContextSession")
  end

  def test_leaves_a_name_that_is_only_a_suffix_alone
    assert_equal "Context", SolidAgent::ModelNaming.base_for("Context")
    assert_equal "Session", SolidAgent::ModelNaming.base_for("Session")
  end

  def test_leaves_an_unsuffixed_name_alone
    assert_equal "Conversation", SolidAgent::ModelNaming.base_for("Conversation")
  end

  def test_accepts_symbols_and_classes
    assert_equal "Chat", SolidAgent::ModelNaming.base_for(:ChatContext)
  end

  def test_derives_sibling_class_names
    assert_equal "ChatMessage", SolidAgent::ModelNaming.message_class_for("ChatContext")
    assert_equal "ChatGeneration", SolidAgent::ModelNaming.generation_class_for("ChatSession")
    assert_equal "SessionMessage", SolidAgent::ModelNaming.message_class_for("SessionContext")
  end
end

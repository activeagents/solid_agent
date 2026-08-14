# frozen_string_literal: true

# A support agent whose conversation outlives the request.
#
# `has_context :conversation, contextual: :user` persists the prompt, the
# assistant's reply, and the tool exchange in between to the tables the
# install generator created — agent_contexts, agent_messages and
# agent_generations — keyed by the record passed as params[:user].
#
# The macro defines the methods used below (load_conversation,
# conversation_messages, conversation_result, conversation_summary, ...).
# Name the context something else and the methods rename with it.
#
# Docs: https://docs.activeagents.ai/solid_agent/context
class SupportAgent < ApplicationAgent
  include SolidAgent::HasContext

  generate_with :openai, model: "gpt-4o-mini"

  has_context :conversation, contextual: :user

  # Multi-turn: load the stored conversation, append this turn's question,
  # and send the whole history as the prompt.
  #
  # Nothing here writes to the database. With auto_save on (the default),
  # SolidAgent persists the last prompt message as the user turn and the
  # response as the assistant turn, both after the provider call — so the
  # next request replays this exchange. Add messages by hand only with
  # `auto_save: false`, or the turn is stored twice.
  #
  # `contextual: :user` alone would create the context for you, but it runs
  # after the prompt is built — a conversation has to be loaded *before*
  # that to replay its messages, so load it explicitly here.
  def answer
    load_conversation(contextable: params[:user])

    prompt messages: conversation_messages + [
      { role: "user", content: params[:message] }
    ]
  end

  # Contexts are keyed by (contextable, agent_name, action_name), so a
  # second action gets its own row rather than appending to the chat
  # history. To work against an existing conversation from a different
  # entry point, load it by id instead of by contextable.
  def summarize
    load_conversation(context_id: params[:conversation_id])

    prompt messages: conversation_messages + [
      { role: "user", content: "Summarize this conversation in three bullet points." }
    ]
  end
end

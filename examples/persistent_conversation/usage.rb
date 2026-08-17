# frozen_string_literal: true

# Persistent conversation — rails console walkthrough.
#
# Docs: https://docs.activeagents.ai/solid_agent/context

user = User.first

# Turn one. The context row, the user message and the assistant message are
# all written during generate_now.
SupportAgent.with(user: user, message: "My invoice is wrong").answer.generate_now

# Turn two. The agent replays turn one from the database before asking.
SupportAgent.with(user: user, message: "It's the VAT line").answer.generate_now

conversation = AgentContext.for_agent("SupportAgent").find_by(contextable: user)

conversation.messages.chronological.map { |m| [ m.role, m.content ] }
# => [["user", "My invoice is wrong"],
#     ["assistant", "..."],
#     ["user", "It's the VAT line"],
#     ["assistant", "..."]]

conversation.total_tokens        # cumulative across both turns
conversation.generations.count   # => 2, one row per provider call

# Every generation carries what produced it: model, finish reason, token
# split, duration, raw provider payload, and a provenance snapshot of the
# agent/prompt/context checksums at the time.
generation = conversation.generations.last
generation.model                 # => "gpt-4o-mini"
generation.total_tokens
generation.estimated_cost        # => USD estimate via SolidAgent::ModelPricing
generation.provenance["agent_checksum"]

# Thread a distributed trace id through prompt_options and the generation
# joins up with your telemetry:
#
#   def answer
#     prompt_options[:trace_id] = Current.trace_id
#     ...
#   end
#
AgentGeneration.with_trace("some-trace-id")
AgentContext.with_trace("some-trace-id")

# Reading a conversation back for a UI is plain Active Record — the
# generated models are yours, scopes included.
conversation.messages.assistant_messages.last&.content
AgentContext.for_agent("SupportAgent").recent.limit(10)
user.agent_contexts if user.respond_to?(:agent_contexts) # add the has_many yourself

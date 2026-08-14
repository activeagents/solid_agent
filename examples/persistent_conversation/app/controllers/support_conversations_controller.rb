# frozen_string_literal: true

# The web side of a persisted conversation: one POST per turn, and a show
# action that renders the history straight out of the database — no session
# state, no cache, nothing to warm up after a deploy.
class SupportConversationsController < ApplicationController
  def show
    @conversation = AgentContext
      .for_agent("SupportAgent")
      .for_action("answer")
      .find_by!(contextable: current_user)

    @messages = @conversation.messages.chronological
  end

  def create
    response = SupportAgent.with(
      user: current_user,
      message: params.require(:message)
    ).answer.generate_now

    render json: { reply: response.message.content }
  end
end

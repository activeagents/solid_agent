# frozen_string_literal: true

# The client half of StreamsToolUpdates. The agent broadcasts to whatever
# string it was handed as params[:stream_id], so the channel just streams
# from that name.
#
#   // app/javascript/channels/tool_status_channel.js
#   consumer.subscriptions.create(
#     { channel: "ToolStatusChannel", stream_id: streamId },
#     { received({ tool_status }) {
#         document.getElementById("status").textContent = tool_status.description
#       } }
#   )
class ToolStatusChannel < ApplicationCable::Channel
  def subscribed
    stream_id = params[:stream_id].to_s

    # Scope the id to the current user so one subscriber can't listen in on
    # another's run.
    reject unless stream_id.start_with?("tool_status:#{current_user.id}:")

    stream_from stream_id
  end
end

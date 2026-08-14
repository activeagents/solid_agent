# frozen_string_literal: true

module SolidAgent
  # The one place that knows how a context class name maps to its message and
  # generation class names.
  #
  # Two callers derive these names — HasContext#infer_class_names at runtime and
  # the context generator when writing files — and they used to implement the
  # rule independently, which is how they drifted.
  module ModelNaming
    # Suffixes a context class may end with. Only the first match is stripped:
    # chaining +delete_suffix+ reduces "SessionContext" to "" and produces a
    # bare "Message"/"Generation" pair that collides across every context.
    CONTEXT_SUFFIXES = %w[Context Session].freeze

    class << self
      # The stem a context class name contributes to its siblings.
      #
      # @param class_name [String, Symbol, Class]
      # @return [String]
      #
      # @example
      #   base_for("ChatSession")     #=> "Chat"
      #   base_for("SessionContext")  #=> "Session"
      #   base_for("Conversation")    #=> "Conversation"
      def base_for(class_name)
        name = class_name.to_s
        suffix = CONTEXT_SUFFIXES.find { |candidate| name.end_with?(candidate) && name != candidate }

        suffix ? name.delete_suffix(suffix) : name
      end

      # @param class_name [String, Symbol, Class]
      # @return [String]
      def message_class_for(class_name) = "#{base_for(class_name)}Message"

      # @param class_name [String, Symbol, Class]
      # @return [String]
      def generation_class_for(class_name) = "#{base_for(class_name)}Generation"
    end
  end
end

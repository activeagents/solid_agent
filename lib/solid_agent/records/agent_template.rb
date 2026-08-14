# frozen_string_literal: true

module SolidAgent
  module Records
    # Behavior for the +AgentTemplate+ record: a named, reusable agent
    # configuration that new agents are stamped out of.
    #
    # A template holds the same configuration columns an agent holds —
    # provider, model, instructions, tools, and so on — and knows how to copy
    # them onto a fresh agent record for an owner. It is a prototype, not a
    # parent: the agent gets a snapshot, and later edits to the template never
    # reach agents already created from it.
    #
    # What this concern deliberately leaves to the host:
    #
    # * *Catalog copy.* Seeded template libraries pin provider model IDs
    #   ("gpt-4o", "claude-sonnet-4-20250514"). Shipping those from a gem would
    #   hand its release cadence to vendor deprecation schedules, so seeds stay
    #   in the application that curates them.
    # * *Merchandising.* Category, featured, popularity, public/free-tier — and
    #   the usage counter that ranks them — describe how one product sells
    #   templates. A persistence gem whose schema asserts a pricing model is
    #   wrong. Every reference here to such a column is guarded with
    #   +has_attribute?+ so hosts that add them still work.
    #
    # In place of a usage counter, {#create_agent_for} instruments
    # {USED_EVENT}. Counting is a subscriber's job, which lets a dashboard
    # increment a column, a metrics backend emit a gauge, and a plain host app
    # do nothing at all — from the same code path.
    #
    # @example Stamping an agent out of a template
    #   template = AgentTemplate.find_by!(slug: "code-assistant")
    #   agent = template.create_agent_for(current_user, name: "My Reviewer")
    #   agent.persisted? #=> true
    #
    # @example Counting template usage from the host
    #   ActiveSupport::Notifications.subscribe("template.used.solid_agent") do |*, payload|
    #     payload[:template].increment!(:usage_count)
    #   end
    module AgentTemplate
      extend ActiveSupport::Concern

      # Emitted after an agent is successfully created from a template.
      # Payload: +:template+, +:agent+, +:owner+, and +:category+ when the
      # host has added that column.
      USED_EVENT = "template.used.solid_agent"

      # Columns copied verbatim onto the new agent. Identity (name, slug),
      # ownership and lifecycle are handled separately — those are the
      # agent's own, not the template's.
      CONFIGURATION_ATTRIBUTES = %w[
        description
        provider
        model
        instructions
        preset_type
        appearance
        instruction_sets
        tools
        mcp_servers
        model_config
      ].freeze

      included do
        validates :name, presence: true
        # Slugs are the stable handle hosts seed and link templates by
        # (`find_by(slug: "code-assistant")`), so uniqueness is global rather
        # than scoped the way an agent's slug is scoped to its owner.
        validates :slug, presence: true, uniqueness: true
      end

      # The configuration this template stamps onto an agent.
      #
      # Only attributes the template actually has are included, so a host that
      # trims columns it does not use — or adds them later — needs no change
      # here.
      #
      # @return [Hash{String => Object}]
      def template_configuration
        CONFIGURATION_ATTRIBUTES.each_with_object({}) do |attribute, config|
          config[attribute] = self[attribute] if has_attribute?(attribute)
        end
      end

      # Builds and saves an agent for +owner+ from this template.
      #
      # Returns the agent whether or not it saved — unsaved with errors
      # populated, the way +create+ does — because callers render those errors.
      # {USED_EVENT} fires only on a successful save.
      #
      # @param owner [Object] the record the agent belongs to (user, account, …)
      # @param name [String, nil] overrides the template's name
      # @return [Object] an instance of {SolidAgent.agent_model}
      # @raise [SolidAgent::Error] when no agent model is configured or generated
      #
      # @example Overriding just the name
      #   template.create_agent_for(account, name: "Release Notes Writer")
      def create_agent_for(owner, name: nil)
        model = SolidAgent.agent_model!

        # Intersect with the agent's columns rather than assuming the two
        # schemas match: template and agent drift independently once a host
        # starts editing generated migrations.
        attributes = template_configuration.slice(*model.column_names)
        attributes["name"] = name.presence || self.name
        attributes["status"] = :draft if draft_status?(model)

        agent = model.new(attributes)
        # Ownable maps `owner` onto whichever column the host actually has.
        # A single-tenant install may have none, and creating an unowned agent
        # is a legitimate outcome there, not an error worth raising.
        agent.owner = owner if agent.respond_to?(:owner=)

        if agent.save
          ActiveSupport::Notifications.instrument(USED_EVENT, used_event_payload(agent, owner))
        end

        agent
      end

      private

      # A template stamps out drafts, not live agents — but only where the host
      # modeled a draft state. On a bare integer column with no enum the symbol
      # casts to nil and trips the NOT NULL constraint, so there the database
      # default is the better answer than a guess.
      def draft_status?(model)
        column = model.columns_hash["status"]
        return false unless column
        return true unless column.type == :integer

        model.defined_enums["status"]&.key?("draft") || false
      end

      def used_event_payload(agent, owner)
        payload = { template: self, agent: agent, owner: owner }
        payload[:category] = self[:category] if has_attribute?(:category)
        payload
      end
    end
  end
end

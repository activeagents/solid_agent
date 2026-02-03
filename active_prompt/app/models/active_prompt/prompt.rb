# frozen_string_literal: true

module ActivePrompt
  # Prompt represents a versioned AI agent configuration.
  #
  # Each prompt has a name, version, and configuration that defines
  # the agent's behavior, model, tools, and instructions.
  #
  # @example Creating a prompt
  #   prompt = ActivePrompt::Prompt.create!(
  #     name: "browser-assistant",
  #     version: "1.0.0",
  #     model: "anthropic/claude-sonnet-4-20250514",
  #     instructions: "You are a browser automation assistant...",
  #     tools: [{ name: "navigate", ref: "@playwright/mcp" }]
  #   )
  #
  # @example Finding the latest version
  #   prompt = ActivePrompt::Prompt.latest("browser-assistant")
  #
  class Prompt < ApplicationRecord
    self.table_name = "active_prompt_prompts"

    # Associations
    has_many :versions, class_name: "ActivePrompt::PromptVersion", dependent: :destroy
    has_many :sessions, class_name: "ActivePrompt::Session", dependent: :destroy

    # Validations
    validates :name, presence: true,
                     format: { with: /\A[a-z][a-z0-9\-]*\z/, message: "must be lowercase with hyphens" },
                     uniqueness: { scope: :version, message: "already exists for this version" }
    validates :version, presence: true,
                        format: { with: /\A\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?\z/, message: "must be valid semver" }
    validates :model, presence: true

    # Serialized attributes
    serialize :tools, coder: JSON
    serialize :config, coder: JSON
    serialize :extensions, coder: JSON

    # Callbacks
    before_validation :set_defaults
    after_create :register_with_active_prompt

    # Scopes
    scope :by_name, ->(name) { where(name: name) }
    scope :by_version, ->(version) { where(version: version) }
    scope :latest_versions, -> {
      select("DISTINCT ON (name) *").order("name, created_at DESC")
    }
    scope :active, -> { where(active: true) }
    scope :with_tools, -> { where("tools IS NOT NULL AND tools != '[]'") }

    class << self
      # Find the latest version of a prompt by name
      #
      # @param name [String] Prompt name
      # @return [Prompt, nil]
      def latest(name)
        by_name(name).order(Arel.sql("string_to_array(version, '.')::int[] DESC")).first
      end

      # Find a specific version of a prompt
      #
      # @param name [String] Prompt name
      # @param version [String] Version string
      # @return [Prompt]
      # @raise [ActiveRecord::RecordNotFound]
      def find_version(name, version)
        by_name(name).by_version(version).first!
      end

      # Create a new version of an existing prompt
      #
      # @param name [String] Prompt name
      # @param bump [Symbol] Version bump type (:major, :minor, :patch)
      # @param attributes [Hash] Updated attributes
      # @return [Prompt]
      def create_new_version(name, bump: :patch, **attributes)
        current = latest(name)

        new_version = if current
                        bump_version(current.version, bump)
                      else
                        "1.0.0"
                      end

        base_attributes = current&.attributes&.except("id", "created_at", "updated_at") || {}
        create!(base_attributes.merge(attributes).merge(name: name, version: new_version))
      end

      # Build an agent class from a prompt
      #
      # @param name [String] Prompt name
      # @param version [String, nil] Optional version (latest if nil)
      # @return [Class]
      def build_agent(name, version: nil)
        prompt = version ? find_version(name, version) : latest(name)
        prompt.to_agent_class
      end

      private

      def bump_version(version, bump)
        parts = version.split(".").map(&:to_i)

        case bump
        when :major
          [parts[0] + 1, 0, 0].join(".")
        when :minor
          [parts[0], parts[1] + 1, 0].join(".")
        when :patch
          [parts[0], parts[1], parts[2] + 1].join(".")
        else
          raise ArgumentError, "Invalid bump type: #{bump}"
        end
      end
    end

    # Convert prompt to a SolidAgent manifest
    #
    # @return [SolidAgent::AgentManifest::Manifest]
    def to_manifest
      SolidAgent::AgentManifest::Manifest.new(
        name: name,
        version: version,
        description: description,
        model: model,
        config: config || {},
        instructions: instructions,
        tools: build_tools,
        extensions: extensions || {}
      )
    end

    # Build an agent class from this prompt
    #
    # @param base_class [Class, nil] Optional base class
    # @return [Class]
    def to_agent_class(base_class: nil)
      SolidAgent::AgentManifest::AgentBuilder.build(
        to_manifest,
        base_class: base_class || ActivePrompt.configuration.agent_base_class.constantize
      )
    end

    # Instantiate an agent from this prompt
    #
    # @param params [Hash] Parameters to pass to the agent
    # @return [Object]
    def build_agent(params: {})
      klass = to_agent_class
      klass.new(params)
    end

    # Create a new session for this prompt
    #
    # @param user [Object, nil] Optional user/owner
    # @param metadata [Hash] Optional metadata
    # @return [Session]
    def create_session(user: nil, metadata: {})
      sessions.create!(
        user: user,
        metadata: metadata,
        state: :active
      )
    end

    # Check if this is the latest version
    #
    # @return [Boolean]
    def latest?
      self.class.latest(name)&.id == id
    end

    # Get all versions of this prompt
    #
    # @return [ActiveRecord::Relation]
    def all_versions
      self.class.by_name(name).order(Arel.sql("string_to_array(version, '.')::int[] DESC"))
    end

    # Duplicate prompt with new version
    #
    # @param bump [Symbol] Version bump type
    # @return [Prompt]
    def duplicate(bump: :patch)
      self.class.create_new_version(name, bump: bump, **attributes.except("id", "version", "created_at", "updated_at"))
    end

    private

    def set_defaults
      self.version ||= "1.0.0"
      self.model ||= ActivePrompt.configuration.default_model
      self.tools ||= []
      self.config ||= {}
      self.extensions ||= {}
      self.active = true if active.nil?
    end

    def register_with_active_prompt
      ActivePrompt.register_prompt(name, version: version, config: attributes)
    end

    def build_tools
      (tools || []).map do |tool_def|
        if tool_def.is_a?(Hash)
          SolidAgent::AgentManifest::Tool.new(
            name: tool_def["name"] || tool_def[:name],
            description: tool_def["description"] || tool_def[:description],
            input_schema: tool_def["input_schema"] || tool_def[:input_schema],
            ref: tool_def["ref"] || tool_def[:ref]
          )
        else
          tool_def
        end
      end
    end
  end
end

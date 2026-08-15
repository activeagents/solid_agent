# frozen_string_literal: true

module SolidAgent
  module Records
    # Version history for an agent's configuration.
    #
    # Every time an agent's versioned attributes change, the host writes a new
    # row holding a full snapshot of the configuration at that moment. Snapshots
    # are whole, not deltas: a version has to be restorable on its own, long
    # after the rows around it were pruned, and diffing is cheap enough to do in
    # Ruby.
    #
    # The +agent+ association is named with the configured class *string*
    # (SolidAgent.agent_class) rather than a constant, so the host can point the
    # records layer at +Ai::Assistant+ without the gem ever touching an
    # autoloadable constant during load.
    #
    # Nothing here uses jsonb operators, so the concern works the same on
    # Postgres, MySQL and sqlite; comparison happens in Ruby.
    #
    # @example Diffing two versions
    #   v2.diff(v1)
    #   #=> { "model" => { from: "gpt-4o-mini", to: "gpt-4o" },
    #   #     "tools" => { from: nil, to: ["search"] } }
    #
    # @example Walking the history
    #   version.previous      #=> the next-lower version, or nil at v1
    #   version.next_version  #=> the next-higher version, or nil at the tip
    module AgentVersion
      extend ActiveSupport::Concern

      included do
        # class_name is read as a String at include time — the host configures
        # SolidAgent in an initializer, which always runs before app/models is
        # autoloaded, and Rails resolves the string to a class only on first
        # use. Constantizing here instead would pin a class that a code reload
        # then replaces.
        # optional: false is spelled out rather than inherited from the host's
        # belongs_to_required_by_default: agent_id is NOT NULL, so an app that
        # loads older Rails defaults would otherwise trade a validation error
        # for a NotNullViolation.
        belongs_to :agent, class_name: SolidAgent.agent_class.to_s, optional: false

        # Mirrors the unique index on [agent_id, version_number]. The index is
        # the real guarantee; the validation exists to fail with a readable
        # error instead of a RecordNotUnique from the adapter.
        validates :version_number, presence: true, uniqueness: { scope: :agent_id }
        validates :configuration_snapshot, presence: true

        scope :recent, -> { order(version_number: :desc) }
        scope :by_version, ->(number) { where(version_number: number) }
      end

      # Compares this version's snapshot against another's.
      #
      # The result is keyed by configuration key and reads from the *other*
      # version to this one, so `newer.diff(older)` describes what the newer
      # version changed.
      #
      # Both key sets are unioned, which means a key dropped in this version is
      # reported as `{ from: <old value>, to: nil }` rather than silently
      # skipped. Keys are compared as strings, because a snapshot built in
      # memory carries symbol keys while one loaded from a json column carries
      # strings, and the two must not read as a wholesale rewrite.
      #
      # @param other_version [#configuration_snapshot, nil]
      # @return [Hash{String => Hash}] changed keys to +{ from:, to: }+
      #
      # @example A removed key
      #   v1.update!(configuration_snapshot: { "model" => "gpt-4o", "tools" => ["search"] })
      #   v2.update!(configuration_snapshot: { "model" => "gpt-4o" })
      #   v2.diff(v1) #=> { "tools" => { from: ["search"], to: nil } }
      def diff(other_version)
        return {} unless other_version

        mine = normalized_snapshot(configuration_snapshot)
        theirs = normalized_snapshot(other_version.configuration_snapshot)

        (mine.keys | theirs.keys).each_with_object({}) do |key, changes|
          before = theirs[key]
          after = mine[key]
          changes[key] = { from: before, to: after } unless before == after
        end
      end

      # The nearest version below this one, or nil when this is the first.
      #
      # @return [ActiveRecord::Base, nil]
      def previous
        sibling_versions.where("version_number < ?", version_number).order(version_number: :desc).first
      end

      # The nearest version above this one, or nil when this is the tip.
      #
      # @return [ActiveRecord::Base, nil]
      def next_version
        sibling_versions.where("version_number > ?", version_number).order(version_number: :asc).first
      end

      # Whether no higher-numbered version exists for the same agent.
      #
      # Answered from the version table alone rather than by asking the agent
      # for its latest version: the gem owns no part of the host's Agent model
      # and must not require it to expose a +latest_version+ reader.
      #
      # @return [Boolean]
      def latest?
        return false if version_number.nil?

        !sibling_versions.where("version_number > ?", version_number).exists?
      end

      # Whether this is version 1.
      #
      # Deliberately a property of the numbering, not of the surviving rows —
      # after old versions are pruned the oldest remaining row is not the
      # initial configuration and should not claim to be.
      #
      # @return [Boolean]
      def initial?
        version_number == 1
      end

      private

      # Versions of the same agent, queried through the concrete host class.
      # Going through the class rather than +agent.agent_versions+ keeps the
      # gem from assuming what the host named the inverse association, and
      # avoids loading the agent row just to walk sibling versions.
      def sibling_versions
        self.class.where(agent_id: agent_id)
      end

      def normalized_snapshot(snapshot)
        return {} if snapshot.blank?

        snapshot.to_h.transform_keys(&:to_s)
      end
    end
  end
end

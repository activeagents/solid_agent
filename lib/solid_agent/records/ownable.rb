# frozen_string_literal: true

module SolidAgent
  module Records
    # Configurable ownership for the agent records.
    #
    # Tenancy is the one thing every application has already decided before it
    # installs this gem. The platform scopes agents to a plain +user_id+; a
    # multi-tenant host scopes them to an account, a workspace, an organization.
    # Hardcoding +belongs_to :user+ would force one of those to migrate, and
    # hardcoding nothing would leave every consumer to reinvent the same scope.
    #
    # So the concern declares the association from two class attributes, and
    # everything else in the gem talks to it through the +owner+ pair — which is
    # why {AgentTemplate#create_agent_for} can assign an owner it knows nothing
    # about.
    #
    # The +belongs_to+ is declared with a class *name*, never a class: host
    # models are autoloaded, and constantizing +User+ while the gem's concern is
    # being included either deadlocks the Rails loader or pins a class that the
    # next code reload replaces. It is also +optional: true+, because a
    # single-user install legitimately has agents that belong to nobody.
    #
    # @example The default: agents own a user_id column
    #   class Agent < ApplicationRecord
    #     include SolidAgent::Records::Ownable
    #   end
    #
    #   agent.owner = current_user
    #   Agent.for_owner(current_user)
    #
    # @example A multi-tenant host
    #   class Agent < ApplicationRecord
    #     include SolidAgent::Records::Ownable
    #     owned_by :account, class_name: "Tenancy::Account"
    #   end
    #
    #   Agent.owner_foreign_key #=> "account_id"
    module Ownable
      extend ActiveSupport::Concern

      included do
        # instance_writer is off deliberately: ownership mapping is a property
        # of the model, and a record that could rewrite it would make
        # `for_owner` and `owner` disagree for the length of a request.
        class_attribute :owner_association, instance_writer: false, default: :user
        class_attribute :owner_class_name, instance_writer: false, default: "User"

        declare_owner_association

        # Restricts to one owner — and to nothing at all when the host has no
        # ownership column, where it returns every record instead of raising.
        # A single-tenant install still calls `for_owner(current_user)` from
        # shared code paths, and there the honest answer to "which of these are
        # yours" is "all of them", not StatementInvalid.
        scope :for_owner, ->(owner) {
          klass.owner_column? ? where(klass.owner_foreign_key => owner) : all
        }
      end

      class_methods do
        # Points ownership at a different association.
        #
        # @param association [Symbol, String] association name, e.g. +:account+
        # @param class_name [String, nil] owner model name; defaults to the
        #   association name camelized
        # @param options [Hash] passed through to +belongs_to+ (+foreign_key+,
        #   +inverse_of+, +optional: false+ to require an owner, …)
        # @return [void]
        #
        # @example Requiring an owner
        #   owned_by :account, class_name: "Account", optional: false
        def owned_by(association, class_name: nil, **options)
          self.owner_association = association.to_sym
          self.owner_class_name = (class_name.presence || association.to_s.camelize).to_s

          declare_owner_association(**options)
        end

        # The column ownership is stored in.
        #
        # Read from the reflection rather than assembled from the association
        # name, so a host that passed a custom +foreign_key+ to {owned_by} gets
        # the column it actually chose.
        #
        # @return [String]
        def owner_foreign_key
          reflect_on_association(owner_association)&.foreign_key&.to_s || "#{owner_association}_id"
        end

        # Whether this model actually stores an owner.
        #
        # Consults the schema rather than the declaration: the association is
        # always declared, and a host that generated the tables without an
        # ownership column is a supported install, not a broken one.
        #
        # @return [Boolean]
        def owner_column?
          column_names.include?(owner_foreign_key)
        end

        private

        def declare_owner_association(**options)
          belongs_to owner_association, **{ class_name: owner_class_name, optional: true }.merge(options)
        end
      end

      # The record this one belongs to, or nil when the host stores no owner.
      #
      # Defined as a method rather than +alias_method+ because the underlying
      # association is per-class configuration: an alias would bind to whatever
      # {owned_by} had been called with at include time, and a subclass that
      # re-owned itself would silently keep reading the parent's association.
      #
      # @return [Object, nil]
      def owner
        return nil unless self.class.owner_column?

        public_send(self.class.owner_association)
      end

      # @param record [Object, nil] the owning record
      # @return [Object, nil] the assigned record
      def owner=(record)
        public_send(:"#{self.class.owner_association}=", record)
      end
    end
  end
end

# frozen_string_literal: true

require "active_agent/providers/mock_provider"

module ActiveAgent
  module Providers
    # A second provider identity for backend-swap tests.
    #
    # Swapping providers is the interesting case — it rebuilds provider
    # configuration rather than merging over it — but proving that needs two
    # distinct services, and every real provider drags in a vendor SDK that
    # solid_agent has no reason to depend on. This one borrows Mock's request
    # and options types while reporting its own service name, which is exactly
    # the seam the swap exercises.
    class FakeProvider < MockProvider
      # Type resolution walks the class name to find Options/RequestType;
      # point it back at Mock's, which are what this provider actually uses.
      def self.namespace = ActiveAgent::Providers::Mock
    end
  end
end

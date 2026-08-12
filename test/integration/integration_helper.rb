# frozen_string_literal: true

# Integration harness: real ActiveAgent, real ActiveSupport.
#
# The unit harness in test/test_helper.rb hand-rolls stand-ins for Rails,
# ActiveSupport::Concern, class_attribute, blank?/present? and friends so the
# unit tests run without Rails installed. Its mock `Rails` constant alone is
# enough to break this file: ActiveAgent requires its railtie whenever Rails
# is defined, so `require "active_agent"` raises LoadError in a process that
# has loaded the unit harness. The two cannot coexist.
#
# Hence this separate directory and its own rake task (`rake test:integration`).
# Anything that needs a genuine ActiveAgent::Base — the provider tool loop,
# prompt_options, generation callbacks — belongs here.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("support", __dir__)

require "active_support/all"
require "active_support/test_case"
require "active_model"
require "action_view"
require "abstract_controller"

require "active_agent"
require "active_agent/base"
require "active_agent/providers/mock_provider"

require "solid_agent"

require "minitest/autorun"

# Two provider identities, neither needing a vendor SDK: :mock for ordinary
# generation, :fake as a swap target for backend tests.
ActiveAgent.configuration[:mock] = { service: "Mock", model: "mock-model" }
ActiveAgent.configuration[:fake] = { service: "Fake", model: "fake-model" }

# Stands in for the host application's ApplicationAgent.
class ApplicationAgent < ActiveAgent::Base
  generate_with :mock, model: "mock-model"
end

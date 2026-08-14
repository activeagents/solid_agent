# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "mocha/minitest"

# This harness stands in for Rails so the unit suite runs without it. What it
# no longer stands in for is ActiveSupport: lib/solid_agent.rb requires the
# core extensions the gem calls, so `blank?`, `presence`, `extract_options!`,
# the String inflections and ActiveSupport::Concern all arrive real. The
# hand-rolled versions that used to live here were not merely redundant — the
# inflections were defined *after* `require "solid_agent"` and so overwrote
# ActiveSupport's, leaving the suite to exercise a toy `camelize` while
# production ran the real one.
#
# Mocks below are for what the gem does not require: Rails, ActionCable,
# ActionView, ActiveRecord::Base, ActiveModel and class_attribute.

# Mock ActionView for template errors
module ActionView
  class MissingTemplate < StandardError; end
end

# Mock ActiveModel
module ActiveModel
  module Model
    def self.included(base)
      base.extend ClassMethods
      base.include Validations
    end

    module ClassMethods
      def model_name
        @model_name ||= OpenStruct.new(
          name: name&.split("::")&.last || "Model",
          singular: (name&.split("::")&.last || "model").downcase,
          plural: (name&.split("::")&.last || "models").downcase + "s"
        )
      end
    end

    def initialize(attributes = {})
      attributes.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end
    end

    def persisted?
      false
    end
  end

  module Validations
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def validates(field, options = {})
        @validations ||= {}
        @validations[field] = options
      end

      def validate(method_name = nil, &block)
        @custom_validations ||= []
        @custom_validations << (method_name || block)
      end

      def validations
        @validations || {}
      end

      def custom_validations
        @custom_validations || []
      end
    end

    def valid?
      @errors = ErrorsHash.new
      self.class.validations.each do |field, options|
        value = send(field)
        if options[:presence] && value.blank?
          @errors.add(field, "can't be blank")
        end
        if options[:format] && value.present?
          regex = options[:format][:with]
          unless value =~ regex
            @errors.add(field, options[:format][:message] || "is invalid")
          end
        end
        if options[:allow_blank] && value.blank?
          # Skip other validations if blank is allowed and value is blank
        end
      end
      @errors.empty?
    end

    def errors
      @errors ||= ErrorsHash.new
    end

    class ErrorsHash < Hash
      def add(field, message)
        self[field] ||= []
        self[field] << message
      end

      def full_messages
        flat_map { |field, messages| messages.map { |m| "#{field} #{m}" } }
      end

      def empty?
        values.all?(&:empty?)
      end
    end
  end
end

require "ostruct"

# Mock class_attribute from ActiveSupport
class Module
  def class_attribute(*attrs)
    options = attrs.last.is_a?(Hash) ? attrs.pop : {}

    attrs.each do |attr|
      # Store defaults in class variable
      default_value = options[:default]

      define_singleton_method(attr) do
        if instance_variable_defined?(:"@#{attr}")
          instance_variable_get(:"@#{attr}")
        else
          # Check parent class
          if superclass.respond_to?(attr)
            superclass.send(attr)
          else
            default_value
          end
        end
      end

      define_singleton_method(:"#{attr}=") do |value|
        instance_variable_set(:"@#{attr}", value)
      end

      define_method(attr) do
        self.class.send(attr)
      end

      define_method(:"#{attr}=") do |value|
        self.class.send(:"#{attr}=", value)
      end

      # Set default if provided
      if options.key?(:default)
        instance_variable_set(:"@#{attr}", default_value)
      end
    end
  end
end

# Mock Rails logger
module Rails
  class << self
    def logger
      @logger ||= MockLogger.new
    end

    def root
      Pathname.new(File.expand_path("../fixtures", __FILE__))
    end
  end

  class MockLogger
    def info(msg); end
    def warn(msg); end
    def error(msg); end
    def debug(msg); end
  end
end

# Mock ActionCable
module ActionCable
  class << self
    def server
      @server ||= MockServer.new
    end
  end

  class MockServer
    attr_reader :broadcasts

    def initialize
      @broadcasts = []
    end

    def broadcast(channel, data)
      @broadcasts << { channel: channel, data: data }
    end

    def clear!
      @broadcasts.clear
    end
  end
end

# Mock ActiveRecord::Base for context models
module ActiveRecord
  class Base
    attr_accessor :attributes

    def initialize(attrs = {})
      @attributes = attrs
      attrs.each do |key, value|
        instance_variable_set(:"@#{key}", value)
        define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        define_singleton_method(:"#{key}=") { |v| instance_variable_set(:"@#{key}", v) }
      end
    end

    def self.find(id)
      new(id: id)
    end

    def self.find_or_create_by!(attrs)
      record = new(attrs)
      yield(record) if block_given?
      record
    end

    def self.create!(attrs = {})
      new(attrs)
    end
  end
end

# Mock URI for URL parsing
require "uri"

# Mock Time.current and iso8601
class Time
  def self.current
    Time.now
  end

  def iso8601
    strftime("%Y-%m-%dT%H:%M:%S%z")
  end
end

require "solid_agent"

# Test fixtures and helpers
module SolidAgentTestHelpers
  # Mock context model
  class MockAgentContext
    attr_accessor :id, :contextable, :agent_name, :action_name, :instructions,
                  :options, :trace_id, :messages, :generations, :input_params,
                  :created_at, :updated_at, :total_input_tokens, :total_output_tokens

    def initialize(attrs = {})
      @messages = []
      @generations = []
      @created_at = Time.now
      @updated_at = Time.now
      @total_input_tokens = 0
      @total_output_tokens = 0
      attrs.each do |key, value|
        send(:"#{key}=", value) if respond_to?(:"#{key}=")
      end
      # Extract input_params from options hash if present
      if @options.is_a?(Hash) && @options[:input_params]
        @input_params = @options[:input_params]
      end
    end

    def total_tokens
      (total_input_tokens || 0) + (total_output_tokens || 0)
    end

    def self.find(id)
      new(id: id)
    end

    def self.find_or_create_by!(attrs)
      record = new(attrs)
      yield(record) if block_given?
      record
    end

    def self.create!(attrs = {})
      new(attrs)
    end

    def record_generation!(response)
      @generations << response
    end
  end

  # Mock message model
  class MockAgentMessage
    attr_accessor :id, :role, :content

    def initialize(attrs = {})
      attrs.each do |key, value|
        send(:"#{key}=", value) if respond_to?(:"#{key}=")
      end
    end

    def self.create!(attrs = {})
      new(attrs)
    end

    def to_message_hash
      { role: role, content: content }
    end
  end

  # Mock generation model
  class MockAgentGeneration
    attr_accessor :id, :response

    def initialize(attrs = {})
      attrs.each do |key, value|
        send(:"#{key}=", value) if respond_to?(:"#{key}=")
      end
    end
  end

  # Mock generation response
  class MockGenerationResponse
    attr_accessor :message, :raw_response

    def initialize(content: nil)
      @message = MockMessage.new(content: content) if content
    end
  end

  class MockMessage
    attr_accessor :content

    def initialize(content:)
      @content = content
    end
  end

  # Base mock agent class simulating ActiveAgent::Base
  class MockBaseAgent
    class << self
      attr_accessor :after_prompt_callbacks, :around_generation_callbacks

      def after_prompt(method_name)
        @after_prompt_callbacks ||= []
        @after_prompt_callbacks << method_name
      end

      def around_generation(method_name)
        @around_generation_callbacks ||= []
        @around_generation_callbacks << method_name
      end

      def inherited(subclass)
        subclass.after_prompt_callbacks = (after_prompt_callbacks || []).dup
        subclass.around_generation_callbacks = (around_generation_callbacks || []).dup
      end
    end

    attr_accessor :params, :prompt_options

    def initialize
      @params = {}
      @prompt_options = {}
    end

    def action_name
      "test_action"
    end

    def agent_name
      name = self.class.name || "test_agent"
      name.underscore
    end

    def prompt(options = {})
      @prompt_options.merge!(options)
    end

    def render_to_string(options = {})
      "{}"
    end

    # Simulate running callbacks
    def run_after_prompt_callbacks
      (self.class.after_prompt_callbacks || []).each do |callback|
        send(callback)
      end
    end

    def run_around_generation(&block)
      result = nil
      (self.class.around_generation_callbacks || []).each do |callback|
        result = send(callback) { block.call }
      end
      result || block.call
    end
  end
end

# Pathname mock if needed
require "pathname"

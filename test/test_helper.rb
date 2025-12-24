# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "mocha/minitest"

# Add present? and blank? methods to core classes
class Object
  def present?
    !blank?
  end

  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

class NilClass
  def blank?
    true
  end

  def present?
    false
  end
end

class String
  def blank?
    empty? || /\A[[:space:]]*\z/.match?(self)
  end
end

class Array
  def blank?
    empty?
  end
end

class Hash
  def blank?
    empty?
  end
end

# Mock ActionView for template errors
module ActionView
  class MissingTemplate < StandardError; end
end

# Mock ActiveSupport::Concern before loading solid_agent
module ActiveSupport
  module Concern
    def self.extended(base)
      base.instance_variable_set(:@_dependencies, [])
    end

    def included(base = nil, &block)
      if base.nil?
        if instance_variable_defined?(:@_included_block)
          raise "Multiple 'included' blocks in #{self}"
        end
        @_included_block = block
      else
        super
      end
    end

    def class_methods(&block)
      @_class_methods_module ||= Module.new
      @_class_methods_module.module_eval(&block)
    end

    def append_features(base)
      if base.instance_variable_defined?(:@_dependencies)
        base.instance_variable_get(:@_dependencies) << self
        false
      else
        return false if base < self
        @_dependencies&.each { |dep| base.include(dep) }
        super
        base.extend(@_class_methods_module) if instance_variable_defined?(:@_class_methods_module)
        base.class_eval(&@_included_block) if instance_variable_defined?(:@_included_block)
      end
    end
  end
end

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

# Add extract_options! to Array
class Array
  def extract_options!
    if last.is_a?(Hash)
      pop
    else
      {}
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

# String extensions
class String
  def underscore
    gsub(/::/, "/")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end

  def camelize
    split("_").map(&:capitalize).join
  end

  def singularize
    # Simple singularize for testing
    # Words ending in 'sis' should not be singularized (analysis, basis, etc.)
    if end_with?("ies")
      self[0..-4] + "y"
    elsif end_with?("ses") && !end_with?("sis")
      self[0..-3]
    elsif end_with?("xes")
      self[0..-3]
    elsif end_with?("sis") || end_with?("ss")
      self
    elsif end_with?("s")
      self[0..-2]
    else
      self
    end
  end

  def humanize
    gsub(/_/, " ").capitalize
  end

  def constantize
    names = split("::")
    names.shift if names.empty? || names.first.empty?

    constant = Object
    names.each do |name|
      constant = constant.const_get(name)
    end
    constant
  end

  def delete_suffix(suffix)
    end_with?(suffix) ? self[0...-suffix.length] : self.dup
  end
end

# Pathname mock if needed
require "pathname"

# frozen_string_literal: true

module SolidAgent
  module AgentManifest
    # Base error class for all AgentManifest errors
    class Error < SolidAgent::Error; end

    # Raised when parsing a manifest file fails
    class ParseError < Error; end

    # Raised when manifest validation fails
    class ValidationError < Error; end

    # Raised when an unknown format is encountered
    class UnknownFormatError < Error; end

    # Raised when exporting a manifest fails
    class ExportError < Error; end

    # Raised when registry operations fail
    class RegistryError < Error; end

    # Raised when schema parsing or conversion fails
    class SchemaError < Error; end
  end
end

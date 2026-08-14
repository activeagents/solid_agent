# frozen_string_literal: true

require "test_helper"

# The examples/ directory is documentation that ships as code, so it gets
# the checks documentation can't have: every Ruby file has to parse, every
# manifest has to validate against the real validator, and every example
# has to be reachable from the index.
class ExamplesTest < Minitest::Test
  EXAMPLES_ROOT = File.expand_path("../examples", __dir__)

  def test_every_ruby_example_parses
    ruby_files = Dir.glob(File.join(EXAMPLES_ROOT, "**", "*.rb"))

    refute_empty ruby_files, "expected examples/ to contain Ruby files"

    ruby_files.each do |path|
      RubyVM::InstructionSequence.compile(File.read(path, encoding: "UTF-8"), path)
    rescue SyntaxError => e
      flunk "#{relative(path)} does not parse: #{e.message}"
    end
  end

  def test_every_manifest_example_is_valid
    manifests = Dir.glob(File.join(EXAMPLES_ROOT, "**", "*.agent.md"))

    refute_empty manifests, "expected examples/ to contain a .agent.md manifest"

    manifests.each do |path|
      errors = SolidAgent::AgentManifest.validate(path)

      assert_empty errors, "#{relative(path)} is not a valid manifest: #{errors.join('; ')}"
    end
  end

  def test_every_example_is_listed_in_the_index
    index = File.read(File.join(EXAMPLES_ROOT, "README.md"), encoding: "UTF-8")

    example_dirs.each do |dir|
      assert_includes index, "(#{dir})",
        "examples/README.md does not link to examples/#{dir}"
    end
  end

  def test_examples_do_not_reference_removed_apis
    # Cheap guard against the examples drifting from the concerns they
    # document: every SolidAgent constant they name has to exist.
    referenced = Dir.glob(File.join(EXAMPLES_ROOT, "**", "*.rb"))
      .flat_map { |path| File.read(path, encoding: "UTF-8").scan(/SolidAgent::([A-Z][A-Za-z:]*)/) }
      .flatten
      .uniq

    refute_empty referenced

    referenced.each do |constant|
      assert SolidAgent.const_defined?(constant),
        "examples reference SolidAgent::#{constant}, which does not exist"
    end
  end

  private

  def example_dirs
    Dir.children(EXAMPLES_ROOT)
      .select { |entry| File.directory?(File.join(EXAMPLES_ROOT, entry)) }
      .sort
  end

  def relative(path)
    path.delete_prefix("#{File.dirname(EXAMPLES_ROOT)}/")
  end
end

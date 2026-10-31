# frozen_string_literal: true

require "test_helper"

# The migration templates are what `rails generate solid_agent:*` writes into
# a host application, and they run on whatever database that application
# has. The records harness deliberately never executes them (see
# test/records/records_helper.rb), so this is a reading of the files: no
# template may name a type only PostgreSQL has, and every one that declares a
# JSON column has to carry the helper that picks the type at migration time.
class GeneratorTemplatesTest < Minitest::Test
  # The templates carry UTF-8 comments; read them as such whatever the locale.
  def self.read(path)
    File.read(path, encoding: "UTF-8")
  end

  TEMPLATES = Dir[File.expand_path("../lib/generators/solid_agent/**/templates/*.rb.erb", __dir__)].sort
  MIGRATIONS = TEMPLATES.select { |path| read(path).include?("ActiveRecord::Migration") }

  def test_there_are_migration_templates_to_check
    assert_operator MIGRATIONS.size, :>=, 8, MIGRATIONS.inspect
  end

  def test_no_template_declares_a_postgresql_only_column_type
    # A column declared as jsonb, through the table definition or add_column.
    # The json_type helper itself names :jsonb, on purpose, and is not a declaration.
    offenders = TEMPLATES.select { |path| self.class.read(path).match?(/\bt\.jsonb\b|add_column [^\n]*:jsonb\b/) }

    assert_empty offenders.map { |path| path.delete_prefix(File.expand_path("..", __dir__) + "/") },
                 "jsonb is PostgreSQL's; declare the column with json_type instead"
  end

  def test_every_migration_with_a_json_column_picks_the_type_at_migration_time
    MIGRATIONS.each do |path|
      source = self.class.read(path)
      next unless source.include?("json_type")

      assert_includes source, "def json_type", path
      assert_includes source, "def json_default", path
      assert_match(/connection\.adapter_name/, source, path)
    end
  end

  def test_json_columns_are_declared_through_the_helpers
    MIGRATIONS.each do |path|
      source = self.class.read(path)
      source.scan(/(?:t\.column|add_column) [^\n]*json_type[^\n]*/).each do |declaration|
        next unless declaration.include?("default")

        assert_match(/\*\*json_default\((\{\}|\[\])\)/, declaration, "#{path}: #{declaration}")
      end
    end
  end
end

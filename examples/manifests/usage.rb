# frozen_string_literal: true

# Portable agent manifests — rails console walkthrough.
#
# A manifest is an agent definition that lives in a file instead of a class:
# frontmatter for the model, tools, input/output schemas and framework
# extensions, Markdown for the instructions. It can be reviewed in a pull
# request, shipped to another framework, or loaded into a running app.
#
# Docs: https://docs.activeagents.ai/solid_agent/manifests
# Format spec: https://github.com/activeagents/solid_agent/blob/main/docs/agent-md-spec.md

path = "examples/manifests/changelog_writer.agent.md"

# --- Read ---------------------------------------------------------------

manifest = SolidAgent::AgentManifest.parse(path)
manifest.name           # => "changelog-writer"
manifest.model          # => "anthropic/claude-sonnet-4-20250514"
manifest.tools.map(&:name)
manifest.instructions   # the Markdown body
manifest.fingerprint    # stable digest — the version an agent ran under

# `load` takes anything: a path, a URL, a JSON/YAML string, or a Hash.
SolidAgent::AgentManifest.load("https://example.com/agents/support.agent.md")
SolidAgent::AgentManifest.load({ name: "quick", model: "openai/gpt-4o-mini" })

# --- Validate -----------------------------------------------------------

SolidAgent::AgentManifest.validate(path)          # => [] when valid
SolidAgent::AgentManifest.valid?(path)            # => true
SolidAgent::AgentManifest.validate(path, strict: true)
SolidAgent::AgentManifest.validate!(path)         # raises ValidationError

# Worth wiring into CI, so a broken manifest fails the build rather than a
# request:
Dir["config/agents/**/*.agent.md"].flat_map { |f| SolidAgent::AgentManifest.validate(f) }

# --- Build --------------------------------------------------------------

# Build an agent class from the manifest. The class arrives configured but
# not finished: it inherits from ApplicationAgent, includes the concerns
# the manifest asked for, carries the manifest's tool schemas, and keeps
# the model, provider and instructions as class attributes.
klass = SolidAgent::AgentManifest.load_agent(path, class_name: "ChangelogWriterAgent")

klass._manifest_provider      # => "anthropic"
klass._manifest_model         # => "claude-sonnet-4-20250514"
klass._manifest_instructions  # the Markdown body
klass._manifest               # the Manifest itself, fingerprint included
klass.new.tools.map { |t| t[:name] } # => ["list_merged_pulls"]

# `activeagent.class_name` in the frontmatter names the constant, so
# passing class_name: here is only needed to override it. Name it either
# way when persisting context — contexts are keyed by class name, and an
# anonymous class has none.

# What the manifest does not carry is behaviour: actions and tool bodies
# are still Ruby. Reopen the class and supply them.
#
#   class ChangelogWriterAgent
#     generate_with _manifest_provider.to_sym, model: _manifest_model
#
#     def write
#       prompt instructions: _manifest_instructions,
#              message: params[:message],
#              tools: tools
#     end
#
#     # Declared tools raise NotImplementedError until you define them.
#     def list_merged_pulls(repository:, from: nil, to: nil)
#       GitHub.merged_pulls(repository, from: from, to: to)
#     end
#   end
#
#   ChangelogWriterAgent.with(message: "Release 1.2.0").write.generate_now

# --- Convert ------------------------------------------------------------

SolidAgent::AgentManifest.parser_formats    # what can be read
SolidAgent::AgentManifest.exporter_formats  # what can be written

# Import someone else's definition...
SolidAgent::AgentManifest.parse("agents.yaml")            # CrewAI
SolidAgent::AgentManifest.parse("basic.prompt")           # Google Dotprompt
SolidAgent::AgentManifest.parse("copilot.prompt.md")      # GitHub Copilot

# ...and export yours for them.
SolidAgent::AgentManifest.export(manifest, :dotprompt)
SolidAgent::AgentManifest.convert(path, :crewai, "tmp/agents.yaml")

# --- Provenance ---------------------------------------------------------

# What an agent ran under, checksummed — pairs with the provenance
# HasContext records on every generation.
SolidAgent::AgentManifest.provenance(manifest)

# `.agent.md` Specification

**Version:** 0.1.0-draft
**Status:** Draft
**Authors:** ActiveAgents Contributors
**License:** Apache 2.0

## Overview

`.agent.md` is an open, portable format for defining AI agents. It uses Markdown with YAML frontmatter to create human-readable, version-control-friendly agent definitions that can be shared across frameworks and platforms.

### Design Goals

1. **Human Readable** - Authors can read and write agents without tooling
2. **Portable** - Agents can run on multiple frameworks (ActiveAgent, CrewAI, LangChain, Genkit)
3. **Git-Friendly** - Clean diffs, easy code review, works with existing workflows
4. **Standards-Based** - Builds on existing specs (Dotprompt, MCP, JSON Schema, AGENTS.md)
5. **Extensible** - Framework-specific features via namespaced sections

## File Structure

```
┌─────────────────────────────────────┐
│ ---                                 │  YAML Frontmatter
│ name: my-agent                      │  (structured metadata)
│ model: anthropic/claude-sonnet-4-20250514    │
│ ...                                 │
│ ---                                 │
├─────────────────────────────────────┤
│ # Agent Title                       │  Markdown Body
│                                     │  (instructions + prompt template)
│ You are a helpful assistant...      │
│                                     │
│ {{#if context}}                     │  Handlebars templating
│ Consider: {{context}}               │
│ {{/if}}                             │
└─────────────────────────────────────┘
```

## Frontmatter Schema

### Meta Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique identifier (lowercase, hyphens) |
| `version` | string | No | SemVer version (default: "1.0.0") |
| `description` | string | No | Brief description (max 280 chars) |
| `author` | string | No | Author name or organization |
| `license` | string | No | SPDX license identifier |
| `repository` | string | No | Source repository URL |
| `tags` | string[] | No | Categorization tags |
| `extends` | string | No | Parent agent to inherit from |

```yaml
---
name: research-assistant
version: 1.2.0
description: An agent that researches topics and synthesizes findings
author: activeagents
license: MIT
repository: https://github.com/activeagents/research-assistant
tags: [research, web, summarization, rag]
extends: "@activeagents/base-assistant"
---
```

### Model Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `model` | string | Yes | Model identifier (`provider/model-name`) |
| `config` | object | No | Model-specific parameters |
| `config.temperature` | number | No | Sampling temperature (0.0-2.0) |
| `config.max_tokens` | number | No | Maximum response tokens |
| `config.top_p` | number | No | Nucleus sampling parameter |
| `config.stop` | string[] | No | Stop sequences |

```yaml
model: anthropic/claude-sonnet-4-20250514
config:
  temperature: 0.7
  max_tokens: 4096
  top_p: 0.9
```

#### Model Identifier Format

```
provider/model-name[:version]

Examples:
  anthropic/claude-sonnet-4-20250514
  openai/gpt-4o
  google/gemini-2.0-flash
  ollama/llama3:70b
  azure/gpt-4o:2024-05-13
```

### Input Schema

Defines the expected input parameters using [Picoschema](#picoschema) (compact) or [JSON Schema](#json-schema) (full).

```yaml
# Picoschema (compact, Dotprompt-compatible)
input:
  schema:
    query: string, the research question to investigate
    depth?: string(shallow, moderate, deep), how thorough the research should be
    max_sources?: integer, maximum number of sources to cite

# OR JSON Schema (full)
input:
  schema:
    type: object
    properties:
      query:
        type: string
        description: The research question to investigate
      depth:
        type: string
        enum: [shallow, moderate, deep]
        default: moderate
      max_sources:
        type: integer
        minimum: 1
        maximum: 20
        default: 5
    required: [query]
```

### Output Schema

Defines the expected output format and structure.

```yaml
output:
  format: json  # json | text | markdown
  schema:
    summary: string, executive summary of findings
    confidence: number, confidence score 0-1
    sources: [object], list of referenced sources
      url: string, source URL
      title: string, page title
      snippet: string, relevant excerpt
      relevance: number, relevance score 0-1
    follow_up?: [string], suggested follow-up questions
```

### Tools Definition

Tools follow [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) conventions for maximum portability.

```yaml
tools:
  # Inline definition
  - name: web_search
    description: Search the web for information
    inputSchema:
      type: object
      properties:
        query:
          type: string
          description: Search query
        num_results:
          type: integer
          default: 10
          maximum: 50
      required: [query]

  # Reference to external tool file
  - $ref: "./tools/navigate.tool.json"

  # Reference to tool pack
  - $ref: "@activeagents/web-tools/search"
```

#### Tool File Format (`.tool.json`)

Standalone tool definitions compatible with MCP:

```json
{
  "name": "navigate",
  "description": "Navigate to a URL and extract page content",
  "inputSchema": {
    "type": "object",
    "properties": {
      "url": {
        "type": "string",
        "format": "uri",
        "description": "The URL to navigate to"
      },
      "extract": {
        "type": "string",
        "enum": ["text", "html", "markdown"],
        "default": "markdown"
      }
    },
    "required": ["url"]
  }
}
```

### Resources (MCP-compatible)

External data sources the agent can access:

```yaml
resources:
  - name: company_docs
    description: Internal company documentation
    uri: "file:///docs/**/*.md"
    mimeType: text/markdown

  - name: api_spec
    description: API specification
    uri: "https://api.example.com/openapi.json"
    mimeType: application/json
```

### Framework Extensions

Framework-specific configuration lives in namespaced sections. Other frameworks SHOULD ignore unrecognized namespaces.

#### ActiveAgent Extension

```yaml
activeagent:
  class_name: ResearchAssistantAgent
  parent_class: ApplicationAgent
  concerns:
    - has_context:
        contextual: user
        context_name: research_session
    - has_tools: [web_search, navigate, summarize]
    - streams_tool_updates:
        channel: research_progress
  callbacks:
    before_prompt: validate_query
    after_generation: log_research
  queued: true  # Run via ActiveJob
```

#### CrewAI Extension

```yaml
crewai:
  role: Senior Research Analyst
  goal: Conduct thorough research and provide actionable insights
  backstory: >
    You are a seasoned research analyst with 15 years of experience
    in investigative journalism and academic research.
  allow_delegation: true
  verbose: true
```

#### LangChain Extension

```yaml
langchain:
  agent_type: openai-tools
  memory:
    type: conversation_buffer
    max_tokens: 4000
  callbacks:
    - langsmith
```

## Markdown Body

The body contains the agent's instructions and prompt template using Markdown with optional Handlebars templating.

### Structure

```markdown
# Agent Title

Brief description of the agent's purpose.

## Instructions

Core behavioral instructions for the agent.

## Guidelines

Specific rules and constraints.

## Examples

{{#if include_examples}}
### Example 1: Basic Query
User: What is quantum computing?
Assistant: [Example response...]
{{/if}}

## Context

{{#if context}}
Consider the following context:
{{context}}
{{/if}}

## Task

{{task}}
```

### Templating

Uses [Handlebars](https://handlebarsjs.com/) syntax (Dotprompt-compatible):

| Syntax | Description |
|--------|-------------|
| `{{variable}}` | Insert variable (HTML-escaped) |
| `{{{variable}}}` | Insert variable (raw, unescaped) |
| `{{#if condition}}...{{/if}}` | Conditional block |
| `{{#unless condition}}...{{/unless}}` | Negative conditional |
| `{{#each items}}...{{/each}}` | Iteration |
| `{{> partial}}` | Include partial template |

#### Built-in Variables

| Variable | Description |
|----------|-------------|
| `{{input.*}}` | Input schema fields |
| `{{context}}` | Loaded context (if using HasContext) |
| `{{messages}}` | Conversation history |
| `{{tools}}` | Available tool descriptions |
| `{{datetime}}` | Current ISO datetime |
| `{{agent.name}}` | Agent name from frontmatter |

### Sections

Reserved section headers with semantic meaning:

| Section | Purpose |
|---------|---------|
| `# {Title}` | Agent title (H1) |
| `## Instructions` | Core behavioral instructions |
| `## Guidelines` | Rules and constraints |
| `## Examples` | Few-shot examples |
| `## Context` | Dynamic context insertion |
| `## Task` | The specific task template |
| `## Output Format` | Expected output structure |

## Picoschema

Picoschema is a compact, YAML-optimized schema format (from Dotprompt):

### Scalar Types

| Type | Description |
|------|-------------|
| `string` | Text value |
| `integer` | Whole number |
| `number` | Decimal number |
| `boolean` | true/false |
| `any` | Any type |

### Modifiers

| Syntax | Meaning |
|--------|---------|
| `field?` | Optional field |
| `field: type, description` | Field with description |
| `field: type(a, b, c)` | Enum values |
| `field: [type]` | Array of type |
| `field: [object]` | Array of objects (indent children) |

### Examples

```yaml
# Simple types
name: string
age: integer
score: number
active: boolean

# Optional fields
nickname?: string
metadata?: any

# With descriptions
email: string, user's email address
priority: integer, 1-5 priority level

# Enums
status: string(draft, published, archived)
size: string(small, medium, large)

# Arrays
tags: [string]
scores: [number]

# Nested objects
author: object
  name: string
  email: string

# Array of objects
comments: [object]
  author: string
  text: string
  timestamp: string
```

## File Organization

### Single-File Agent

```
my-agent.agent.md
```

### Multi-File Agent (Package)

```
my-agent/
├── agent.md                    # Main definition (required)
├── README.md                   # Human documentation
├── CHANGELOG.md                # Version history
├── LICENSE                     # License file
│
├── tools/                      # Tool definitions
│   ├── search.tool.json
│   └── analyze.tool.json
│
├── prompts/                    # Partial templates
│   ├── _header.md
│   └── _examples.md
│
├── examples/                   # Example inputs/contexts
│   ├── basic.input.json
│   └── advanced.input.json
│
└── tests/                      # Test cases
    ├── unit.test.yml
    └── integration.test.yml
```

### Package Manifest (`agent.json`)

For published packages:

```json
{
  "name": "@activeagents/research-assistant",
  "version": "1.2.0",
  "description": "An agent that researches topics and synthesizes findings",
  "main": "agent.md",
  "files": [
    "agent.md",
    "tools/*.tool.json",
    "prompts/*.md"
  ],
  "keywords": ["research", "web", "summarization"],
  "author": "ActiveAgents <hello@activeagents.ai>",
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "https://github.com/activeagents/research-assistant"
  },
  "dependencies": {
    "@activeagents/web-tools": "^1.0.0"
  },
  "engines": {
    "activeagent": ">=0.5.0"
  },
  "compatibility": {
    "frameworks": ["activeagent", "crewai", "langchain", "genkit"]
  }
}
```

## Test Format

### Test Cases (`*.test.yml`)

```yaml
name: Research Assistant Tests
agent: ./agent.md

cases:
  - name: basic_research_query
    description: Should handle a simple research question
    input:
      query: "What are the benefits of meditation?"
      depth: shallow
    expect:
      output:
        summary: { contains: "meditation" }
        sources: { min_length: 2 }
        confidence: { gte: 0.7 }
      tools_called: [web_search]
      no_errors: true

  - name: deep_research_with_sources
    description: Should cite multiple sources for deep research
    input:
      query: "Compare quantum computing approaches"
      depth: deep
      max_sources: 10
    expect:
      output:
        sources: { min_length: 5, max_length: 10 }
      tools_called: [web_search, navigate]
      response_time: { lte: 30000 }  # 30 seconds

  - name: handles_invalid_input
    description: Should gracefully handle missing query
    input: {}
    expect:
      error: { contains: "query is required" }
```

### Context Fixtures (`*.context.json`)

```json
{
  "name": "research_context_example",
  "description": "Example context for testing research agent",
  "messages": [
    {
      "role": "user",
      "content": "Research the history of artificial intelligence"
    },
    {
      "role": "assistant",
      "content": "I'll research the history of AI for you..."
    }
  ],
  "metadata": {
    "user_id": "test-user-123",
    "session_id": "sess-456"
  }
}
```

## Registry API

### Package Discovery

```
GET /api/v1/agents
GET /api/v1/agents?q=research&tags=web,rag
GET /api/v1/agents/@activeagents/research-assistant
GET /api/v1/agents/@activeagents/research-assistant/versions
GET /api/v1/agents/@activeagents/research-assistant/1.2.0
```

### Package Publishing

```
POST /api/v1/agents
Authorization: Bearer <token>
Content-Type: multipart/form-data

{package archive}
```

### Response Format

```json
{
  "name": "@activeagents/research-assistant",
  "version": "1.2.0",
  "description": "An agent that researches topics and synthesizes findings",
  "author": {
    "name": "ActiveAgents",
    "url": "https://activeagents.ai"
  },
  "downloads": {
    "total": 15420,
    "weekly": 342
  },
  "stars": 89,
  "license": "MIT",
  "tags": ["research", "web", "summarization"],
  "compatibility": {
    "frameworks": ["activeagent", "crewai", "langchain"],
    "models": ["anthropic/*", "openai/*"]
  },
  "files": {
    "agent.md": "https://cdn.activeagents.ai/...",
    "tools/search.tool.json": "https://cdn.activeagents.ai/..."
  },
  "checksums": {
    "agent.md": "sha256:abc123...",
    "tools/search.tool.json": "sha256:def456..."
  },
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-20T14:22:00Z"
}
```

## CLI Reference

```bash
# Initialize new agent
activeagent init my-agent
activeagent init my-agent --template research

# Validate agent definition
activeagent validate my-agent.agent.md
activeagent validate ./my-agent/

# Test agent locally
activeagent test my-agent.agent.md
activeagent test my-agent.agent.md --input examples/basic.input.json
activeagent test my-agent.agent.md --context examples/research.context.json

# Run agent interactively
activeagent run my-agent.agent.md
activeagent run my-agent.agent.md --input '{"query": "test"}'

# Search registry
activeagent search research
activeagent search --tags web,rag --framework activeagent

# Install from registry
activeagent add @activeagents/research-assistant
activeagent add @activeagents/research-assistant@1.2.0

# Fork agent
activeagent fork @activeagents/research-assistant my-researcher

# Publish to registry
activeagent login
activeagent publish
activeagent publish --tag beta

# Export to other formats
activeagent export my-agent.agent.md --format crewai
activeagent export my-agent.agent.md --format dotprompt
activeagent export my-agent.agent.md --format langchain

# Import from other formats
activeagent import agent.yaml --from crewai
activeagent import prompt.prompt --from dotprompt
```

## Compatibility Matrix

| Feature | ActiveAgent | CrewAI | LangChain | Genkit |
|---------|-------------|--------|-----------|--------|
| Basic metadata | ✅ | ✅ | ✅ | ✅ |
| Model config | ✅ | ✅ | ✅ | ✅ |
| Input schema | ✅ | ⚠️ | ✅ | ✅ |
| Output schema | ✅ | ⚠️ | ✅ | ✅ |
| Tools (MCP) | ✅ | ✅ | ✅ | ✅ |
| Handlebars | ✅ | ⚠️ | ⚠️ | ✅ |
| Framework extensions | ✅ | ✅ | ✅ | ⚠️ |
| Context persistence | ✅ | ❌ | ⚠️ | ❌ |
| Streaming | ✅ | ⚠️ | ✅ | ✅ |

✅ Full support | ⚠️ Partial/adapter needed | ❌ Not supported

## Examples

### Minimal Agent

```markdown
---
name: hello-world
model: openai/gpt-4o
---

# Hello World Agent

You are a friendly assistant. Greet the user warmly.
```

### Research Agent

```markdown
---
name: research-assistant
version: 1.0.0
model: anthropic/claude-sonnet-4-20250514
config:
  temperature: 0.7

input:
  schema:
    query: string, the research question
    depth?: string(shallow, deep)

output:
  format: json
  schema:
    summary: string
    sources: [object]
      url: string
      title: string

tools:
  - name: web_search
    description: Search the web
    inputSchema:
      type: object
      properties:
        query: { type: string }
      required: [query]

activeagent:
  concerns:
    - has_context:
        contextual: user
    - has_tools: [web_search]
---

# Research Assistant

You are a thorough research assistant.

## Instructions

1. Analyze the research query
2. Search for relevant information
3. Synthesize findings with citations

## Task

Research the following:

{{query}}

{{#if depth == "deep"}}
Provide comprehensive analysis with multiple perspectives.
{{else}}
Provide a concise summary with key points.
{{/if}}
```

### Multi-Tool Agent

```markdown
---
name: code-reviewer
version: 2.1.0
model: anthropic/claude-sonnet-4-20250514

tools:
  - $ref: "@activeagents/code-tools/analyze"
  - $ref: "@activeagents/code-tools/search"
  - name: suggest_fix
    description: Suggest a code fix
    inputSchema:
      type: object
      properties:
        file: { type: string }
        issue: { type: string }
        suggestion: { type: string }
      required: [file, issue, suggestion]

activeagent:
  concerns:
    - has_tools: [analyze, search, suggest_fix]
    - streams_tool_updates: true
---

# Code Reviewer

You are an expert code reviewer focused on quality and security.

## Review Checklist

- [ ] Security vulnerabilities
- [ ] Performance issues
- [ ] Code style consistency
- [ ] Test coverage
- [ ] Documentation

## Task

Review the following code and provide actionable feedback:

```{{language}}
{{code}}
```
```

## References

- [Dotprompt](https://github.com/google/dotprompt) - Google's prompt template format
- [MCP](https://modelcontextprotocol.io/) - Model Context Protocol specification
- [AGENTS.md](https://agents.md/) - OpenAI's agent instructions format
- [JSON Schema](https://json-schema.org/) - Schema validation standard
- [Handlebars](https://handlebarsjs.com/) - Templating language
- [SemVer](https://semver.org/) - Semantic versioning

## Changelog

### 0.1.0-draft (2025-01-08)

- Initial draft specification
- Core frontmatter schema
- Picoschema support
- MCP-compatible tools
- Framework extension namespaces
- Test format definition
- Registry API design

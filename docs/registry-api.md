# ActiveAgents Registry API

**Base URL:** `https://api.activeagents.ai/v1`

## Overview

The ActiveAgents Registry is a package repository for shareable AI agents. It follows patterns from npm, RubyGems, and PyPI while adding AI-specific features like model compatibility tracking, sandboxed testing, and framework interoperability.

## Authentication

```http
Authorization: Bearer <api_token>
```

Tokens are obtained via:
- `activeagent login` CLI command
- OAuth flow on activeagents.ai
- API token generation in dashboard

## Core Resources

### Agents (Packages)

An agent package contains:
- `agent.md` - Main definition file
- Tools, prompts, tests, examples
- Metadata (versions, dependencies, compatibility)

### Organizations

Scoped namespaces for agents (e.g., `@activeagents/research-assistant`)

### Users

Individual accounts that can publish and star agents

---

## API Endpoints

### Search & Discovery

#### Search Agents

```http
GET /agents
```

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | string | Full-text search query |
| `tags` | string | Comma-separated tags |
| `framework` | string | Filter by framework compatibility |
| `model` | string | Filter by model compatibility |
| `author` | string | Filter by author/org |
| `sort` | string | `downloads`, `stars`, `updated`, `created` |
| `order` | string | `asc`, `desc` |
| `page` | integer | Page number (default: 1) |
| `per_page` | integer | Results per page (default: 20, max: 100) |

**Example:**

```http
GET /agents?q=research&tags=web,rag&framework=activeagent&sort=downloads
```

**Response:**

```json
{
  "data": [
    {
      "name": "@activeagents/research-assistant",
      "version": "1.2.0",
      "description": "An agent that researches topics and synthesizes findings",
      "author": {
        "name": "ActiveAgents",
        "username": "activeagents"
      },
      "downloads": {
        "total": 15420,
        "weekly": 342
      },
      "stars": 89,
      "license": "MIT",
      "tags": ["research", "web", "summarization", "rag"],
      "compatibility": {
        "frameworks": ["activeagent", "crewai", "langchain"],
        "models": ["anthropic/*", "openai/*"]
      },
      "updated_at": "2025-01-20T14:22:00Z"
    }
  ],
  "meta": {
    "total": 156,
    "page": 1,
    "per_page": 20,
    "total_pages": 8
  }
}
```

#### Get Agent Details

```http
GET /agents/:scope/:name
GET /agents/:name
```

**Example:**

```http
GET /agents/@activeagents/research-assistant
```

**Response:**

```json
{
  "name": "@activeagents/research-assistant",
  "version": "1.2.0",
  "description": "An agent that researches topics and synthesizes findings",
  "readme": "# Research Assistant\n\nA powerful agent for...",
  "author": {
    "name": "ActiveAgents",
    "username": "activeagents",
    "avatar_url": "https://cdn.activeagents.ai/avatars/activeagents.png"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/activeagents/research-assistant"
  },
  "license": "MIT",
  "tags": ["research", "web", "summarization", "rag"],
  "keywords": ["ai", "research", "web-scraping"],

  "downloads": {
    "total": 15420,
    "weekly": 342,
    "daily": 48
  },
  "stars": 89,
  "forks": 12,

  "compatibility": {
    "frameworks": {
      "activeagent": ">=0.5.0",
      "crewai": ">=0.30.0",
      "langchain": ">=0.1.0"
    },
    "models": {
      "anthropic": ["claude-sonnet-4-20250514", "claude-3-5-haiku-*"],
      "openai": ["gpt-4o", "gpt-4o-mini"],
      "google": ["gemini-2.0-*"]
    }
  },

  "dependencies": {
    "@activeagents/web-tools": "^1.0.0",
    "@activeagents/summarization": "^2.1.0"
  },

  "versions": {
    "latest": "1.2.0",
    "stable": "1.2.0",
    "beta": "1.3.0-beta.1"
  },

  "files": {
    "agent.md": {
      "size": 4521,
      "checksum": "sha256:abc123..."
    },
    "tools/search.tool.json": {
      "size": 892,
      "checksum": "sha256:def456..."
    }
  },

  "maintainers": [
    {
      "username": "activeagents",
      "role": "owner"
    }
  ],

  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-20T14:22:00Z"
}
```

#### Get Agent Version

```http
GET /agents/:scope/:name/versions/:version
```

**Example:**

```http
GET /agents/@activeagents/research-assistant/versions/1.2.0
```

**Response:**

```json
{
  "name": "@activeagents/research-assistant",
  "version": "1.2.0",
  "description": "An agent that researches topics and synthesizes findings",

  "manifest": {
    "name": "research-assistant",
    "model": "anthropic/claude-sonnet-4-20250514",
    "tools": ["web_search", "navigate", "summarize"],
    "input": {
      "schema": {
        "query": "string, the research question",
        "depth?": "string(shallow, moderate, deep)"
      }
    }
  },

  "changelog": "## 1.2.0\n\n- Added deep research mode\n- Improved source citation",

  "files": [
    {
      "path": "agent.md",
      "size": 4521,
      "checksum": "sha256:abc123...",
      "download_url": "https://cdn.activeagents.ai/packages/@activeagents/research-assistant/1.2.0/agent.md"
    },
    {
      "path": "tools/search.tool.json",
      "size": 892,
      "checksum": "sha256:def456...",
      "download_url": "https://cdn.activeagents.ai/packages/@activeagents/research-assistant/1.2.0/tools/search.tool.json"
    }
  ],

  "dependencies": {
    "@activeagents/web-tools": "^1.0.0"
  },

  "published_at": "2025-01-20T14:22:00Z",
  "published_by": {
    "username": "activeagents"
  }
}
```

#### List Versions

```http
GET /agents/:scope/:name/versions
```

**Response:**

```json
{
  "data": [
    {
      "version": "1.2.0",
      "tag": "latest",
      "published_at": "2025-01-20T14:22:00Z",
      "downloads": 342
    },
    {
      "version": "1.3.0-beta.1",
      "tag": "beta",
      "published_at": "2025-01-22T09:15:00Z",
      "downloads": 28
    },
    {
      "version": "1.1.0",
      "published_at": "2025-01-10T11:30:00Z",
      "downloads": 8420
    }
  ]
}
```

### Download & Installation

#### Download Package

```http
GET /agents/:scope/:name/-/:name-:version.tgz
```

Returns the packaged agent as a tarball.

**Example:**

```http
GET /agents/@activeagents/research-assistant/-/research-assistant-1.2.0.tgz
```

#### Download Single File

```http
GET /agents/:scope/:name/files/:path
GET /agents/:scope/:name/versions/:version/files/:path
```

**Example:**

```http
GET /agents/@activeagents/research-assistant/files/agent.md
GET /agents/@activeagents/research-assistant/versions/1.2.0/files/tools/search.tool.json
```

### Publishing

#### Publish New Version

```http
PUT /agents/:scope/:name
Authorization: Bearer <token>
Content-Type: application/gzip
```

**Request Body:** gzipped tarball of the agent package

**Headers:**

| Header | Description |
|--------|-------------|
| `x-agent-tag` | Distribution tag (`latest`, `beta`, etc.) |
| `x-agent-access` | Access level (`public`, `restricted`) |

**Response:**

```json
{
  "name": "@activeagents/research-assistant",
  "version": "1.2.0",
  "tag": "latest",
  "published_at": "2025-01-20T14:22:00Z",
  "files": [
    "agent.md",
    "tools/search.tool.json"
  ],
  "size": 12480,
  "checksum": "sha256:abc123..."
}
```

#### Deprecate Version

```http
POST /agents/:scope/:name/versions/:version/deprecate
Authorization: Bearer <token>
```

**Request Body:**

```json
{
  "message": "This version has a critical bug. Please upgrade to 1.2.1"
}
```

#### Unpublish Version

```http
DELETE /agents/:scope/:name/versions/:version
Authorization: Bearer <token>
```

Only allowed within 72 hours of publishing and if no dependents.

### User Actions

#### Star Agent

```http
PUT /agents/:scope/:name/star
Authorization: Bearer <token>
```

#### Unstar Agent

```http
DELETE /agents/:scope/:name/star
Authorization: Bearer <token>
```

#### Fork Agent

```http
POST /agents/:scope/:name/fork
Authorization: Bearer <token>
```

**Request Body:**

```json
{
  "name": "my-research-assistant",
  "scope": "@myorg"
}
```

**Response:**

```json
{
  "name": "@myorg/my-research-assistant",
  "forked_from": "@activeagents/research-assistant",
  "version": "1.0.0",
  "created_at": "2025-01-20T15:00:00Z"
}
```

### Testing & Playground

#### Run Agent in Sandbox

```http
POST /agents/:scope/:name/run
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body:**

```json
{
  "version": "1.2.0",
  "input": {
    "query": "What are the benefits of meditation?",
    "depth": "shallow"
  },
  "options": {
    "model_override": "anthropic/claude-3-5-haiku-latest",
    "timeout": 30000,
    "trace": true
  }
}
```

**Response:**

```json
{
  "run_id": "run_abc123",
  "status": "completed",
  "output": {
    "summary": "Meditation offers numerous benefits...",
    "sources": [
      {
        "url": "https://example.com/meditation-study",
        "title": "Scientific Study on Meditation",
        "relevance": 0.92
      }
    ],
    "confidence": 0.85
  },
  "trace": {
    "tools_called": [
      {
        "name": "web_search",
        "input": {"query": "meditation benefits scientific studies"},
        "output": {"results": [...]},
        "duration_ms": 1250
      }
    ],
    "model_calls": [
      {
        "model": "anthropic/claude-3-5-haiku-latest",
        "input_tokens": 1420,
        "output_tokens": 890,
        "duration_ms": 2100
      }
    ]
  },
  "usage": {
    "total_tokens": 2310,
    "estimated_cost": 0.0023,
    "duration_ms": 4500
  }
}
```

#### Get Run Status

```http
GET /runs/:run_id
Authorization: Bearer <token>
```

For long-running agents, poll this endpoint or use webhooks.

#### Stream Run Output

```http
GET /runs/:run_id/stream
Authorization: Bearer <token>
Accept: text/event-stream
```

Returns Server-Sent Events for real-time streaming:

```
event: tool_start
data: {"tool": "web_search", "input": {"query": "meditation benefits"}}

event: tool_complete
data: {"tool": "web_search", "duration_ms": 1250}

event: chunk
data: {"content": "Meditation offers"}

event: chunk
data: {"content": " numerous benefits..."}

event: complete
data: {"run_id": "run_abc123", "status": "completed"}
```

### Organizations

#### Create Organization

```http
POST /orgs
Authorization: Bearer <token>
```

**Request Body:**

```json
{
  "name": "myorg",
  "display_name": "My Organization",
  "email": "contact@myorg.com"
}
```

#### List Organization Agents

```http
GET /orgs/:org/agents
```

#### Add Organization Member

```http
PUT /orgs/:org/members/:username
Authorization: Bearer <token>
```

**Request Body:**

```json
{
  "role": "developer"
}
```

Roles: `owner`, `admin`, `developer`, `readonly`

### Webhooks

#### Register Webhook

```http
POST /agents/:scope/:name/hooks
Authorization: Bearer <token>
```

**Request Body:**

```json
{
  "url": "https://myapp.com/webhooks/activeagents",
  "events": ["publish", "star", "fork", "run"],
  "secret": "my-webhook-secret"
}
```

#### Webhook Events

| Event | Description |
|-------|-------------|
| `publish` | New version published |
| `deprecate` | Version deprecated |
| `star` | Agent starred |
| `unstar` | Agent unstarred |
| `fork` | Agent forked |
| `run` | Agent run in sandbox |
| `download` | Agent downloaded |

**Webhook Payload:**

```json
{
  "event": "publish",
  "timestamp": "2025-01-20T14:22:00Z",
  "agent": {
    "name": "@activeagents/research-assistant",
    "version": "1.2.0"
  },
  "actor": {
    "username": "activeagents"
  }
}
```

---

## Rate Limits

| Endpoint Type | Authenticated | Anonymous |
|---------------|---------------|-----------|
| Search/Read | 1000/hour | 100/hour |
| Download | 500/hour | 50/hour |
| Publish | 100/hour | N/A |
| Run (Sandbox) | 50/hour | 5/hour |

Rate limit headers:

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1705764000
```

---

## Error Responses

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Agent not found: @activeagents/nonexistent",
    "details": {
      "name": "@activeagents/nonexistent"
    }
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `NOT_FOUND` | 404 | Resource not found |
| `UNAUTHORIZED` | 401 | Missing or invalid auth |
| `FORBIDDEN` | 403 | Permission denied |
| `CONFLICT` | 409 | Version already exists |
| `VALIDATION_ERROR` | 422 | Invalid input |
| `RATE_LIMITED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |

---

## SDK Usage

### Ruby (activeagent gem)

```ruby
require 'activeagent/registry'

# Configure client
ActiveAgent::Registry.configure do |config|
  config.api_token = ENV['ACTIVEAGENT_TOKEN']
end

# Search agents
agents = ActiveAgent::Registry.search(
  q: 'research',
  tags: ['web', 'rag'],
  framework: 'activeagent'
)

# Get agent details
agent = ActiveAgent::Registry.get('@activeagents/research-assistant')
puts agent.version  # => "1.2.0"
puts agent.model    # => "anthropic/claude-sonnet-4-20250514"

# Download and install
ActiveAgent::Registry.install('@activeagents/research-assistant')
# Installs to: vendor/agents/@activeagents/research-assistant/

# Load and use
agent_class = ActiveAgent::Registry.load('@activeagents/research-assistant')
agent = agent_class.new(params: { query: 'What is AI?' })
result = agent.research.generate_now

# Publish
ActiveAgent::Registry.publish(
  path: './my-agent',
  tag: 'latest'
)
```

### JavaScript/TypeScript

```typescript
import { AgentRegistry } from '@activeagents/sdk';

const registry = new AgentRegistry({
  token: process.env.ACTIVEAGENT_TOKEN
});

// Search
const agents = await registry.search({
  q: 'research',
  tags: ['web', 'rag']
});

// Download manifest
const manifest = await registry.getManifest('@activeagents/research-assistant');

// Run in sandbox
const result = await registry.run('@activeagents/research-assistant', {
  input: { query: 'What is AI?' }
});
```

### Python

```python
from activeagents import Registry

registry = Registry(token=os.environ['ACTIVEAGENT_TOKEN'])

# Search
agents = registry.search(q='research', tags=['web', 'rag'])

# Download and convert to CrewAI
manifest = registry.get('@activeagents/research-assistant')
crewai_yaml = registry.export(manifest, format='crewai')

# Run in sandbox
result = registry.run(
    '@activeagents/research-assistant',
    input={'query': 'What is AI?'}
)
```

---

## CLI Reference

```bash
# Authentication
activeagent login                    # OAuth login flow
activeagent logout
activeagent whoami

# Search & Discovery
activeagent search research          # Search for agents
activeagent search --tags web,rag    # Filter by tags
activeagent info @activeagents/research-assistant  # Get details

# Installation
activeagent add @activeagents/research-assistant
activeagent add @activeagents/research-assistant@1.2.0
activeagent add @activeagents/research-assistant --save  # Add to agent.json
activeagent remove @activeagents/research-assistant

# Publishing
activeagent init my-agent            # Create new agent
activeagent validate                 # Validate before publish
activeagent publish                  # Publish to registry
activeagent publish --tag beta       # Publish with tag
activeagent deprecate 1.1.0 --message "Upgrade to 1.2.0"
activeagent unpublish 1.0.0          # Remove version (within 72h)

# Testing
activeagent test                     # Run local tests
activeagent run @activeagents/research-assistant  # Run in sandbox
activeagent run . --input '{"query": "test"}'     # Run local agent

# Organizations
activeagent org create myorg
activeagent org add-member myorg janedoe --role developer
activeagent org list-members myorg

# Utilities
activeagent convert agent.prompt --to agent.md  # Convert formats
activeagent export . --format crewai           # Export to CrewAI
```

---

## Web Interface Features

### Agent Page (activeagents.ai/agents/@activeagents/research-assistant)

- **Overview** - Description, README, quick stats
- **Playground** - Interactive testing with real-time output
- **Versions** - Version history with changelogs
- **Dependencies** - Dependency graph
- **Dependents** - Who uses this agent
- **Files** - Browse package contents
- **Settings** - Maintainer settings (if owner)

### Playground Features

- **Input Editor** - JSON/Form input with schema validation
- **Model Selector** - Test with different models
- **Streaming Output** - Real-time response streaming
- **Tool Trace** - Visual tool execution timeline
- **Cost Estimator** - Token usage and cost tracking
- **Share** - Generate shareable playground links
- **Fork to Sandbox** - One-click fork to edit

### Dashboard

- **My Agents** - Published agents with stats
- **Starred** - Bookmarked agents
- **Recent Runs** - Playground history
- **Usage** - API usage and billing
- **Teams** - Organization management

---

## Pricing Tiers

### Free Tier
- Unlimited public agents
- 100 sandbox runs/month
- 10 MB storage per agent
- Community support

### Pro ($29/month)
- Private agents
- 1,000 sandbox runs/month
- 100 MB storage per agent
- Priority support
- Custom domains

### Team ($99/month)
- Everything in Pro
- 5,000 sandbox runs/month
- Organization management
- SSO/SAML
- Audit logs
- SLA

### Enterprise (Custom)
- Unlimited runs
- Self-hosted option
- Custom integrations
- Dedicated support
- Custom contracts

---

## Future Roadmap

### Phase 1 (Current)
- Basic registry CRUD
- Package publishing
- Search and discovery
- CLI tools

### Phase 2
- Sandbox execution environment
- Interactive playground
- Model compatibility matrix
- Usage analytics

### Phase 3
- Agent marketplace (paid agents)
- Revenue sharing for authors
- Enterprise self-hosted
- CI/CD integrations

### Phase 4
- Agent composition (agents using agents)
- Automated testing infrastructure
- Performance benchmarks
- Security scanning

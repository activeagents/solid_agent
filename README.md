<p align="center">
  <img src="assets/solid_agent.png" alt="SolidAgent" width="200">
</p>

# SolidAgent

SolidAgent extends the [ActiveAgent](https://github.com/activeagents/activeagent) framework with enterprise-grade features for building robust AI agents in Rails applications. It provides three core concerns that add database-backed persistence, declarative tool schemas, and real-time streaming capabilities to your agents.

## Features

- **HasContext** - Database-backed prompt context management for maintaining conversation history and agent state
- **HasTools** - Declarative, schema-based tool definitions compatible with LLM function-calling APIs
- **StreamsToolUpdates** - Real-time UI feedback during tool execution via ActionCable

## Installation

Add this line to your application's Gemfile:

```ruby
gem "solid_agent"
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install solid_agent
```

## Usage

### Quick Start

Generate a new agent with context support:

```bash
$ rails generate solid_agent:agent WritingAssistant --context --context_name conversation --contextable user
```

### HasContext - Persistent Conversation History

Add database-backed context management to your agents:

```ruby
class WritingAssistantAgent < ApplicationAgent
  include SolidAgent::HasContext

  has_context :conversation, contextable: :user

  def improve
    load_conversation(contextable: current_user)
    add_conversation_user_message(params[:message])
    prompt messages: conversation_messages
  end
end
```

This generates helper methods like:
- `load_conversation(contextable:)` - Load or create a context
- `conversation_messages` - Get formatted message history
- `add_conversation_user_message(content)` - Add a user message
- `add_conversation_assistant_message(content)` - Add an AI response
- `conversation_result` - Get the last assistant message

### HasTools - Declarative Tool Schemas

Define tools inline with a clean DSL:

```ruby
class ResearchAgent < ApplicationAgent
  include SolidAgent::HasTools

  tool :search do
    description "Search for information"
    parameter :query, type: :string, required: true
    parameter :limit, type: :integer, default: 10
  end

  def research
    prompt tools: tools
  end

  def search(query:, limit: 10)
    # Tool implementation
  end
end
```

Or use JSON templates in `app/views/research_agent/tools/search.json.erb`.

### StreamsToolUpdates - Real-Time Feedback

Broadcast tool execution status to your UI:

```ruby
class BrowserAgent < ApplicationAgent
  include SolidAgent::HasTools
  include SolidAgent::StreamsToolUpdates

  has_tools :navigate, :click
  tool_description :navigate, ->(args) { "Visiting #{args[:url]}..." }
end
```

### Generators

```bash
# Generate a new agent
$ rails generate solid_agent:agent MyAgent

# Generate with context support
$ rails generate solid_agent:agent MyAgent --context --context_name session

# Generate a tool template
$ rails generate solid_agent:tool search MyAgent --parameters query:string:required

# Generate context models
$ rails generate solid_agent:context conversation
```

## Example Apps

See SolidAgent in action:

- [Fizzy](https://github.com/tonsoffun/fizzy) - AI-enhanced Kanban tracking tool with writing, research, and file analysis agents
- [Writebook](https://github.com/tonsoffun/writebook) - Collaborative writing platform with integrated AI writing assistance, research, and document analysis

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/activeagents/solid_agent.

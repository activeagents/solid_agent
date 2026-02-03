# ActivePrompt

A Rails engine for versioned AI agent prompts with fragment-based context management. ActivePrompt integrates with SolidAgent to provide browser automation agents with Playwright MCP support.

## Features

- **Versioned Prompts**: Track agent configurations with semantic versioning
- **Fragment-based Context**: Cache conversation state for session resumption
- **Browser Automation**: Playwright MCP integration for web automation
- **Authentication Workflows**: Pause/resume for user-assisted authentication
- **Real-time Updates**: ActionCable integration for live status updates

## Installation

Add to your Gemfile:

```ruby
gem "active_prompt"
```

Run the install generator:

```bash
rails generate active_prompt:install
rails db:migrate
```

## Configuration

Configure in `config/initializers/active_prompt.rb`:

```ruby
ActivePrompt.configure do |config|
  # Default model for prompts
  config.default_model = "anthropic/claude-sonnet-4-20250514"

  # Fragment cache store (:memory, :redis, :database)
  config.fragment_cache_store = :database

  # Session timeout
  config.session_timeout = 30.minutes

  # Callback when authentication is required
  config.auth_callback = ->(session, error) {
    # Notify user...
  }
end
```

## Usage

### Simple One-liner Execution

```ruby
# Execute a browser automation task with simple instructions
result = ActivePrompt::BrowserAgent.execute_task(
  "Go to github.com and find the top 3 trending repositories"
)

case result[:status]
when :completed
  puts "Result: #{result[:result]}"
when :waiting_for_auth
  puts "Please log in. Session ID: #{result[:session_id]}"
when :failed
  puts "Error: #{result[:error]}"
end
```

### Creating Prompts

```ruby
# Create a versioned prompt
prompt = ActivePrompt::Prompt.create!(
  name: "browser-assistant",
  version: "1.0.0",
  model: "anthropic/claude-sonnet-4-20250514",
  instructions: "You are a browser automation assistant...",
  tools: [
    { name: "browser_navigate" },
    { name: "browser_click" },
    { name: "browser_snapshot" }
  ]
)

# Create a new version
new_version = prompt.duplicate(bump: :minor)  # -> 1.1.0
```

### Managing Sessions

```ruby
# Create a session
session = prompt.create_session(user: current_user)

# Add messages
session.add_message(role: "user", content: "Navigate to example.com")

# Pause for authentication
session.pause!(reason: :auth, checkpoint: { url: current_url })

# Resume when ready
session.resume!

# Check session status
session.state  # => :active, :paused, :waiting_for_auth, etc.
session.resumable?  # => true/false
```

### Using Fragments

Fragments store intermediate state for session resumption:

```ruby
# Create a browser state fragment
ActivePrompt::Fragment.create_browser_state(
  session: session,
  url: "https://example.com",
  cookies: browser_cookies,
  local_storage: storage_data
)

# Create a tool output fragment
ActivePrompt::Fragment.create_tool_output(
  session: session,
  tool_name: "browser_navigate",
  input: { url: "https://example.com" },
  output: { success: true }
)

# Retrieve fragments
session.fragments.by_type(:browser_state).ordered
session.latest_fragment(:browser_state)
```

### API Endpoints

ActivePrompt exposes RESTful endpoints:

```
# Prompts
GET    /active_prompt/prompts
POST   /active_prompt/prompts
GET    /active_prompt/prompts/:id
PATCH  /active_prompt/prompts/:id
DELETE /active_prompt/prompts/:id
GET    /active_prompt/prompts/latest?name=browser-assistant
POST   /active_prompt/prompts/:id/duplicate

# Sessions
GET    /active_prompt/sessions
GET    /active_prompt/sessions/active
GET    /active_prompt/sessions/resumable
GET    /active_prompt/sessions/:id
POST   /active_prompt/sessions/:id/pause
POST   /active_prompt/sessions/:id/resume
GET    /active_prompt/sessions/:id/fragments
GET    /active_prompt/sessions/:id/messages

# Browser Agent
POST   /active_prompt/browser/execute
POST   /active_prompt/browser/resume
GET    /active_prompt/browser/status
POST   /active_prompt/browser/auth_complete

# Demo Interface
GET    /active_prompt/demo
```

### Real-time Updates with ActionCable

Subscribe to session updates:

```javascript
// In your JavaScript
const cable = ActionCable.createConsumer();

cable.subscriptions.create(
  { channel: "ActivePrompt::SessionChannel", session_id: sessionId },
  {
    received(data) {
      if (data.type === "auth_required") {
        showAuthPrompt(data.message);
      } else if (data.type === "result") {
        displayResult(data);
      }
    }
  }
);

// Signal authentication complete
subscription.send({ type: "auth_complete" });
```

## Authentication Workflows

When the browser agent encounters a login page:

1. Agent detects authentication requirement
2. Session pauses with `waiting_for_auth` state
3. User receives notification (via callback or ActionCable)
4. User completes authentication in the browser
5. User signals completion via API or ActionCable
6. Agent resumes from saved checkpoint

```ruby
# In your application
ActivePrompt.configure do |config|
  config.auth_callback = ->(session, error) {
    # Send push notification, email, etc.
    NotificationService.notify_auth_required(
      user: session.user,
      session_id: session.id,
      url: error.url
    )
  }
end
```

## Fragment Types

- `browser_state`: URL, cookies, local storage
- `browser_snapshot`: DOM snapshot for context
- `tool_output`: Output from tool executions
- `reasoning`: AI reasoning/thinking traces
- `user_input`: User-provided input or decisions
- `checkpoint`: General checkpoint for resumption
- `authentication`: Authentication-related state
- `navigation`: Navigation history

## Dependencies

- Rails >= 7.0
- SolidAgent >= 0.1.0
- ActiveAgent >= 1.0.0

## License

MIT

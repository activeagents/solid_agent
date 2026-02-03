---
name: github-trends
version: 1.0.0
description: Agent that discovers trending repositories on GitHub
author: ActiveAgents Team
license: MIT
repository: https://github.com/activeagents/github-trends-agent
tags: [github, trends, research, browser]

model: anthropic/claude-sonnet-4-20250514
config:
  temperature: 0.3
  max_tokens: 4096

input:
  schema:
    language?: string, Programming language filter (e.g., python, ruby, javascript)
    timeframe?: string(daily, weekly, monthly), Time range for trends
    count?: integer, Number of repositories to return (default 5)

output:
  format: json
  schema:
    repositories:
      type: array
      items:
        type: object
        properties:
          name: string
          url: string
          description: string
          stars: integer
          language: string
          stars_today: integer

tools:
  - name: browser_navigate
    description: Navigate to a URL
    inputSchema:
      type: object
      properties:
        url:
          type: string
          description: URL to navigate to
      required: [url]

  - name: browser_snapshot
    description: Get accessibility snapshot of the current page
    inputSchema:
      type: object
      properties: {}

  - name: browser_click
    description: Click an element on the page
    inputSchema:
      type: object
      properties:
        ref:
          type: string
          description: Element reference from snapshot
        element:
          type: string
          description: Human-readable element description
      required: [ref]

  - name: browser_evaluate
    description: Evaluate JavaScript on the page
    inputSchema:
      type: object
      properties:
        function:
          type: string
          description: JavaScript function to execute
      required: [function]

  - name: browser_wait_for
    description: Wait for text or element
    inputSchema:
      type: object
      properties:
        text:
          type: string
          description: Text to wait for
        time:
          type: number
          description: Time to wait in seconds

  - name: extract_trending_repos
    description: Extract trending repository data from GitHub trending page
    inputSchema:
      type: object
      properties:
        count:
          type: integer
          description: Number of repositories to extract
          default: 5

resources:
  - name: github_trending_url
    uri: https://github.com/trending
    mimeType: text/html
    description: GitHub Trending page

activeagent:
  class_name: GitHubTrendsAgent
  concerns:
    - has_context:
        contextual: false
    - has_tools
    - has_reasons:
        auto_capture: true
    - streams_tool_updates

  callbacks:
    before_prompt:
      - validate_language_filter
    after_prompt:
      - cache_results

examples:
  - input:
      language: python
      timeframe: daily
      count: 3
    output:
      repositories:
        - name: "awesome-project"
          url: "https://github.com/user/awesome-project"
          description: "An awesome Python project"
          stars: 15000
          language: "Python"
          stars_today: 500

tests:
  - name: fetch_daily_trends
    input:
      timeframe: daily
    expect:
      contains: repositories

  - name: filter_by_language
    input:
      language: ruby
    expect:
      all_match:
        language: Ruby
---

# GitHub Trends Agent

You are an AI agent specialized in discovering trending repositories on GitHub.
Your task is to navigate to GitHub's trending page, extract repository information,
and return structured data about the most popular repositories.

## Instructions

1. Navigate to the GitHub trending page
2. If a language filter is specified, select that language
3. If a timeframe is specified, select that time range (daily/weekly/monthly)
4. Extract information about the requested number of repositories
5. Return structured data with repository details

## Key Behaviors

- Always start by navigating to https://github.com/trending
- Use the snapshot tool to understand the page structure
- Click on language/time filters if specified
- Extract repository names, descriptions, star counts, and today's stars
- Handle pagination if more repositories are needed

## Error Handling

- If GitHub is unavailable, report the error clearly
- If a language filter doesn't exist, note it and proceed with all languages
- If authentication is required (rate limiting), pause and request user intervention

## Output Format

Return a JSON object with:
```json
{
  "repositories": [
    {
      "name": "owner/repo-name",
      "url": "https://github.com/owner/repo-name",
      "description": "Repository description",
      "stars": 12345,
      "language": "Python",
      "stars_today": 123
    }
  ],
  "metadata": {
    "language_filter": "python",
    "timeframe": "daily",
    "fetched_at": "2024-01-01T12:00:00Z"
  }
}
```

## Task

{{ #if language }}
Find the top {{ count | default: 5 }} trending {{ language }} repositories
{{ else }}
Find the top {{ count | default: 5 }} trending repositories across all languages
{{ /if }}
for the {{ timeframe | default: "daily" }} timeframe.

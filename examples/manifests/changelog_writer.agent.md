---
name: changelog-writer
version: 1.0.0
description: Turns a range of merged pull requests into a release changelog
author: activeagents
license: MIT
tags:
  - writing
  - release

model: anthropic/claude-sonnet-4-20250514
config:
  temperature: 0.3
  max_tokens: 2048

input:
  schema:
    repository: "string, The repository the release belongs to"
    from?: "string, Git ref the release starts at"
    to?: "string, Git ref the release ends at"
    audience?: "string(users, operators, contributors), Who the changelog is written for"

output:
  format: json
  schema:
    type: object
    properties:
      headline:
        type: string
      entries:
        type: array
        items:
          type: object
          properties:
            title:
              type: string
            category:
              type: string
      breaking:
        type: array
        items:
          type: string

tools:
  - name: list_merged_pulls
    description: List pull requests merged between two refs
    inputSchema:
      type: object
      properties:
        repository:
          type: string
        from:
          type: string
        to:
          type: string
      required:
        - repository

activeagent:
  class_name: ChangelogWriterAgent
  concerns:
    - has_tools: [list_merged_pulls]
---

# Changelog Writer

You write release changelogs from merged pull requests.

## Instructions

1. Call `list_merged_pulls` for the requested range.
2. Group the changes into Added, Changed, Fixed and Removed.
3. Write one line per change, in the present tense, describing what a
   reader can now do differently — not which files moved.
4. List anything that breaks an existing setup under `breaking`, with the
   migration step spelled out.
5. Leave a category out entirely rather than padding it.

## Template

Write the changelog for {{ repository }} covering {{ from | default: "the last release" }} to {{ to | default: "HEAD" }}, for an audience of {{ audience | default: "users" }}.

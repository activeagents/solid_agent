---
name: tool-agent
version: 1.0.0
description: Agent with multiple tools
model: openai/gpt-4o

tools:
  - name: calculate
    description: Perform mathematical calculations
    inputSchema:
      type: object
      properties:
        expression:
          type: string
          description: Mathematical expression to evaluate
      required:
        - expression

  - name: lookup
    description: Look up information in the database
    inputSchema:
      type: object
      properties:
        table:
          type: string
          enum: ["users", "products", "orders"]
        id:
          type: integer
      required:
        - table
        - id

  - $ref: "./shared/common_tools.json#/definitions/logger"
---

# Tool Agent

An agent demonstrating tool definitions.

## Instructions

Use the available tools to help users with calculations and data lookups.

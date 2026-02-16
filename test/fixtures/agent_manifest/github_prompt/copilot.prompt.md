---
model: GPT-4o
tools: ['githubRepo', 'search/codebase', 'vscodeAPI']
description: 'Generate a new React form component with validation'
mode: 'agent'
---

# React Form Generator

Create a React form component for ${input:formName} with the following features:

- Form validation using ${input:validationLibrary}
- TypeScript types for form data
- Accessible form controls with proper labels
- Error message display
- Submit handler with loading state

## Component Structure

The component should follow this pattern:
- Use controlled inputs
- Include proper ARIA attributes
- Handle form submission with async/await
- Show validation errors inline

## Guidelines

- Follow the existing project patterns found in the codebase
- Use the project's existing UI component library if available
- Include unit tests for the form validation logic

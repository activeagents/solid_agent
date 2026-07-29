# frozen_string_literal: true

# Agent-curated long-term memory for a subject record, written and read by
# agents through SolidAgent::HasMemory's save_memory/recall_memory tools.
#
# Memory is scoped to (memorable, scope) — not to an agent class — so any
# agent operating on the same subject shares it, making it a handoff
# channel between agents. Entry source_agent records who wrote each note.
class AgentMemory < ApplicationRecord
  belongs_to :memorable, polymorphic: true, optional: true
  has_many :entries, class_name: "AgentMemoryEntry", dependent: :destroy

  validates :scope, presence: true

  # Finds or creates the memory for a subject.
  def self.for(memorable, scope: SolidAgent::HasMemory::DEFAULT_SCOPE)
    find_or_create_by!(memorable: memorable, scope: scope.to_s)
  end

  # Appends a summary note.
  def remember(content, source_agent: nil, category: nil)
    entries.create!(content: content, source_agent: source_agent, category: category)
  end

  # Most recent notes first.
  def recall(limit: 20, category: nil)
    scope = entries.order(created_at: :desc)
    scope = scope.where(category: category) if category.present?
    scope.limit(limit || 20).to_a
  end

  def forget(entry_id)
    entries.find(entry_id).destroy!
  end

  def summary_list
    entries.order(:created_at).pluck(:content)
  end

  # Formatted block suitable for injecting into another agent's
  # instructions when handing a subject off.
  def to_prompt
    notes = entries.order(:created_at).map do |entry|
      source = entry.source_agent.present? ? " (#{entry.source_agent})" : ""
      "- #{entry.content}#{source}"
    end
    return "" if notes.empty?

    "Memory notes for this subject:\n#{notes.join("\n")}"
  end
end

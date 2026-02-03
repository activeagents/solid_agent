# frozen_string_literal: true

class CreateActivePromptMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :active_prompt_messages do |t|
      t.references :session, null: false, foreign_key: { to_table: :active_prompt_sessions }
      t.string :role, null: false
      t.text :content
      t.text :tool_calls
      t.string :tool_call_id
      t.string :name
      t.text :metadata

      t.timestamps

      t.index [:session_id, :role]
      t.index :created_at
    end
  end
end

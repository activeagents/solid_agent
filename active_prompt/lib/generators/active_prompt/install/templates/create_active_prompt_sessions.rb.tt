# frozen_string_literal: true

class CreateActivePromptSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :active_prompt_sessions do |t|
      t.references :prompt, null: false, foreign_key: { to_table: :active_prompt_prompts }
      t.references :user, polymorphic: true
      t.integer :state, null: false, default: 0
      t.text :metadata
      t.text :browser_state
      t.text :checkpoint_data
      t.datetime :expires_at
      t.datetime :completed_at

      t.timestamps

      t.index :state
      t.index :expires_at
      t.index [:user_type, :user_id, :state]
    end
  end
end

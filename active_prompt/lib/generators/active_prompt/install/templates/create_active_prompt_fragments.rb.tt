# frozen_string_literal: true

class CreateActivePromptFragments < ActiveRecord::Migration[7.0]
  def change
    create_table :active_prompt_fragments do |t|
      t.references :session, null: false, foreign_key: { to_table: :active_prompt_sessions }
      t.string :fragment_type, null: false
      t.integer :sequence_number, null: false
      t.text :content, null: false
      t.text :metadata

      t.timestamps

      t.index [:session_id, :fragment_type]
      t.index [:session_id, :sequence_number]
    end
  end
end

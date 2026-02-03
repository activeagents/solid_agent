# frozen_string_literal: true

class CreateActivePromptPrompts < ActiveRecord::Migration[7.0]
  def change
    create_table :active_prompt_prompts do |t|
      t.string :name, null: false
      t.string :version, null: false, default: "1.0.0"
      t.string :model, null: false
      t.text :description
      t.text :instructions
      t.text :tools
      t.text :config
      t.text :extensions
      t.boolean :active, default: true, null: false

      t.timestamps

      t.index [:name, :version], unique: true
      t.index :name
      t.index :active
    end
  end
end

# frozen_string_literal: true

# SPR-529: comments under wiki pages (SprintlyWikiComment).
class CreateSprintlyWikiComments < ActiveRecord::Migration[6.1]
  def change
    create_table :sprintly_wiki_comments do |t|
      t.integer :page_id, null: false
      t.integer :author_id, null: false
      t.text :content, limit: 16.megabytes, null: false
      t.timestamp :created_on, null: false
      t.timestamp :updated_on, null: false
    end
    add_index :sprintly_wiki_comments, [:page_id, :created_on]
    add_index :sprintly_wiki_comments, :author_id
  end
end

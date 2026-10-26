# frozen_string_literal: true

# SPR-530: labels of wiki pages. A table rather than a JSON document in the settings: rows
# follow the page (by id, so a rename keeps them; deleted with it), a project's labels are one
# indexed query, and two people labelling at once do not overwrite each other.
#
# Versioned by timestamp so migrations added by other branches of this plugin cannot collide.
class CreateSprintlyWikiPageLabels < ActiveRecord::Migration[6.1]
  def change
    create_table :sprintly_wiki_page_labels do |t|
      t.integer :wiki_page_id, null: false
      t.string :name, null: false, limit: 40
      t.datetime :created_on, null: false
    end
    add_index :sprintly_wiki_page_labels, %i[wiki_page_id name], unique: true,
                                                                 name: 'index_sprintly_wiki_page_labels_on_page_and_name'
    add_index :sprintly_wiki_page_labels, :name
  end
end

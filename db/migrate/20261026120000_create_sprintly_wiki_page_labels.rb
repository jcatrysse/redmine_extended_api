# frozen_string_literal: true

# SPR-530: labels of wiki pages. A table rather than a JSON document in the settings: rows
# follow the page (by id, so a rename keeps them; deleted with it), a project's labels are one
# indexed query, and two people labelling at once do not overwrite each other.
#
# Versioned by timestamp so migrations added by other branches of this plugin cannot collide.
#
# Tenants start from a prepared database dump and run `rake redmine:plugins:migrate` when the
# container starts (REDMINE_PLUGINS_MIGRATE, set on the tenant's Swarm service by global-api).
# A dump may already hold the table without its row in schema_migrations, so every step is a
# no-op when its object exists: a failed migration would stop the container from starting.
class CreateSprintlyWikiPageLabels < ActiveRecord::Migration[6.1]
  def change
    create_table :sprintly_wiki_page_labels, if_not_exists: true do |t|
      t.integer :wiki_page_id, null: false
      t.string :name, null: false, limit: 40
      t.datetime :created_on, null: false
    end
    add_index :sprintly_wiki_page_labels, %i[wiki_page_id name], unique: true, if_not_exists: true,
                                                                 name: 'index_sprintly_wiki_page_labels_on_page_and_name'
    add_index :sprintly_wiki_page_labels, :name, if_not_exists: true
  end
end

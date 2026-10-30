# frozen_string_literal: true

require_relative 'access'

module RedmineExtendedApi
  module Sprintly
    # SPR-383: controller-level enforcement of the Sprintly permissions that are finer than
    # the core permission they derive (see Permissions::DERIVED). Each check runs after the
    # controller's own `authorize`, only refuses — never grants — and is inert until the
    # tenant is switched over.
    module ControllerPatches
      module Guard
        private

        def sprintly_enforced?
          ModelPatches.active_for?(User.current)
        end

        def sprintly_allowed?(app_id, project = @project)
          project && User.current.allowed_to?(Permissions.symbol_for(app_id), project)
        end

        def sprintly_deny
          render_403
        end
      end

      # Watching an issue yourself is part of seeing it; adding or removing somebody else is
      # assigning work, so it takes `issues.assign`.
      module WatchersControllerPatch
        include Guard

        def self.prepended(base)
          base.before_action :sprintly_check_watchers, only: %i[create destroy]
        end

        private

        def sprintly_check_watchers
          return true unless sprintly_enforced?

          ids =
            if action_name == 'destroy'
              [params[:user_id]]
            elsif params[:watcher]
              Array(params[:watcher][:user_ids] || params[:watcher][:user_id])
            else
              [params[:user_id]]
            end
          others = ids.flatten.compact.map(&:to_i).uniq - [User.current.id]
          return true if others.empty? || sprintly_allowed?('issues.assign')

          sprintly_deny
        end
      end

      # Sprints are Redmine versions; `manage_versions` lets you do anything to them, the SPA
      # splits it into create / edit (start, complete) / delete.
      module VersionsControllerPatch
        include Guard

        def self.prepended(base)
          base.before_action :sprintly_check_sprint, only: %i[create update destroy]
        end

        private

        def sprintly_check_sprint
          return true unless sprintly_enforced?

          allowed =
            case action_name
            when 'create' then sprintly_allowed?('sprints.create') || sprintly_allowed?('projects.manage_versions')
            when 'destroy' then sprintly_allowed?('sprints.delete') || sprintly_allowed?('projects.manage_versions')
            else %w[sprints.edit sprints.start sprints.complete projects.manage_versions].any? { |id| sprintly_allowed?(id) }
            end
          allowed || sprintly_deny
        end
      end

      # Redmine has one `edit_wiki_pages` for writing a page; creating one is `wiki.create`,
      # changing an existing one `wiki.edit`.
      module WikiControllerPatch
        include Guard

        def self.prepended(base)
          base.before_action :sprintly_check_wiki_write, only: %i[update]
        end

        private

        def sprintly_check_wiki_write
          return true unless sprintly_enforced? && @wiki

          page = @wiki.find_page(params[:id])
          sprintly_allowed?(page ? 'wiki.edit' : 'wiki.create') || sprintly_deny
        end
      end

      # Gists are files of the project's Files module, and core puts all of them under one
      # `manage_files`. Adding one is `gists.create` (FilesController below); renaming one is
      # `gists.edit`, deleting one `gists.delete` — here, for files of a project or a version
      # only: an issue's or a wiki page's attachments keep core's rules.
      module AttachmentsControllerPatch
        include Guard

        def self.prepended(base)
          base.before_action :sprintly_check_gist, only: %i[update destroy]
        end

        private

        def sprintly_check_gist
          return true unless sprintly_enforced? && @attachment

          container = @attachment.container
          return true unless container.is_a?(Project) || container.is_a?(Version)

          project = container.is_a?(Project) ? container : container.project
          sprintly_allowed?(action_name == 'destroy' ? 'gists.delete' : 'gists.edit', project) || sprintly_deny
        end
      end

      module FilesControllerPatch
        include Guard

        def self.prepended(base)
          base.before_action :sprintly_check_gist_create, only: %i[create]
        end

        private

        def sprintly_check_gist_create
          return true unless sprintly_enforced?

          sprintly_allowed?('gists.create') || sprintly_deny
        end
      end

      # Editing: `time.edit` for anybody's entries, `time.edit_own` for your own. Deleting:
      # `time.delete`. (Core lets whoever may edit an entry also delete it.)
      module TimelogControllerPatch
        include Guard

        def self.prepended(base)
          base.before_action :sprintly_check_time_entries, only: %i[update bulk_update destroy]
        end

        private

        def sprintly_check_time_entries
          return true unless sprintly_enforced?

          entries = @time_entries || [@time_entry].compact
          allowed = entries.all? do |entry|
            if action_name == 'destroy'
              sprintly_allowed?('time.delete', entry.project)
            else
              sprintly_allowed?('time.edit', entry.project) ||
                (entry.user_id == User.current.id && sprintly_allowed?('time.edit_own', entry.project))
            end
          end
          allowed || sprintly_deny
        end
      end
    end
  end
end

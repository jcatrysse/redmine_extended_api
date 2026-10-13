# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/hash/slice'
require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern
      include ApiHelpers

      ISSUE_OVERRIDE_ATTRIBUTES  = %i[author_id created_on updated_on closed_on].freeze
      JOURNAL_OVERRIDE_ATTRIBUTES = %i[user_id created_on updated_on updated_by_id].freeze

      # Prepended (Issue.prepend), not alias_method. safe_attributes= is not overridden at all:
      # on Redmine 5.1/6.1 plugins loaded after this one (redmine_tags) alias_method it, and an
      # alias_method chain on a prepended method recurses (stack level too deep). The issue
      # overrides are set before validation instead, on the issue the request updates.
      prepended do
        class_attribute :extended_api_issue_override_attributes, instance_accessor: false
        self.extended_api_issue_override_attributes ||= ISSUE_OVERRIDE_ATTRIBUTES

        before_validation :apply_extended_api_issue_overrides_before_validation
        after_save :apply_extended_api_issue_overrides_after_save
      end

      def init_journal(user, notes = '')
        super.tap do |journal|
          apply_extended_api_journal_overrides_on_init(journal, user)
        end
      end

      private

      def allow_extended_api_overrides?(user)
        user.respond_to?(:admin?) && user.admin?
      end

      # Only the issue the request updates (IssuesControllerPatch sets its id), not other issues
      # saved in the same request (duplicates, rescheduled followers).
      def apply_extended_api_issue_overrides_before_validation
        return if Thread.current[:redmine_extended_api_issue_target_id].blank? || !persisted?
        return unless extended_api_override_target?

        apply_extended_api_issue_overrides(defined?(User) ? User.current : nil)
      end

      # The issue the request updates (its id) or, on create, the one this save inserted; not
      # a parent recalculated or another issue saved along with it, which kept its own author
      # and dates only by luck before (a subtask import overwrote its parent's).
      def extended_api_override_target?
        target_id = Thread.current[:redmine_extended_api_issue_target_id]
        return id.to_s == target_id.to_s if target_id.present?

        respond_to?(:saved_change_to_id?) && saved_change_to_id?
      end

      # Pre-save: set imported values on the Issue instance
      def apply_extended_api_issue_overrides(user)
        overrides = Thread.current[:redmine_extended_api_issue_overrides]

        if overrides.is_a?(Hash) && allow_extended_api_overrides?(user)
          permitted = overrides.slice(*self.class.extended_api_issue_override_attributes).compact
          assign_attributes(permitted) unless permitted.empty?
        end

        # Ensure notify=false is persisted to avoid enqueuing mail jobs via ActiveJob/Sidekiq
        if Thread.current[:redmine_extended_api_suppress_notifications] && respond_to?(:notify=)
          self.notify = false
        end
      end

      # Pre-save: set imported values on the journal instance that Issue just created
      def apply_extended_api_journal_overrides_on_init(journal, user)
        return unless journal.respond_to?(:assign_attributes)

        overrides = Thread.current[:redmine_extended_api_journal_overrides]
        if overrides.is_a?(Hash) && allow_extended_api_overrides?(user)
          permitted = overrides.slice(*JOURNAL_OVERRIDE_ATTRIBUTES).compact
          journal.assign_attributes(permitted) unless permitted.empty?
        end

        # Ensure journal notifications are suppressed when requested
        if Thread.current[:redmine_extended_api_suppress_notifications] && journal.respond_to?(:notify=)
          journal.notify = false
        end
      end

      # Post-save: force issue timestamps/author, bypassing callbacks that overwrite them
      def apply_extended_api_issue_overrides_after_save
        return if Thread.current[:redmine_extended_api_applying_issue_overrides]
        return unless extended_api_override_target?

        overrides = Thread.current[:redmine_extended_api_issue_overrides]
        return unless overrides.is_a?(Hash)
        return unless allow_extended_api_overrides?(User.current)

        cols = {}

        cols[:author_id] = overrides[:author_id] if overrides[:author_id].present?
        cols[:created_on] = parse_extended_api_time(overrides[:created_on]) if overrides[:created_on].present?
        cols[:updated_on] = parse_extended_api_time(overrides[:updated_on]) if overrides[:updated_on].present?
        cols[:closed_on]  = parse_extended_api_time(overrides[:closed_on])  if overrides[:closed_on].present?

        return if cols.empty?

        Thread.current[:redmine_extended_api_applying_issue_overrides] = true
        # Not update_columns: since Rails 7.1 it adds "lock_version = <in memory value>" to the
        # WHERE, and on create the nested set callbacks have already bumped lock_version in the
        # database, so the update hit no row and the overrides were silently lost.
        self.class.where(id: id).update_all(cols)
        assign_attributes(cols)
        clear_attribute_changes(cols.keys)
      ensure
        Thread.current[:redmine_extended_api_applying_issue_overrides] = nil
      end
    end
  end
end

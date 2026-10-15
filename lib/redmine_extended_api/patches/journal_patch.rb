# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/hash/slice'

module RedmineExtendedApi
  module Patches
    module JournalPatch
      extend ActiveSupport::Concern
      include ApiHelpers

      EXTENDED_API_JOURNAL_OVERRIDE_ATTRIBUTES = %i[user_id created_on updated_on updated_by_id].freeze

      # Callbacks, not an override of Issue#init_journal (see IssuePatch). Only the journal the
      # request writes on the issue it updates gets the overrides, not journals written on other
      # issues in the same request (duplicates, relations).
      included do
        class_attribute :extended_api_journal_override_attributes, instance_accessor: false
        self.extended_api_journal_override_attributes ||= EXTENDED_API_JOURNAL_OVERRIDE_ATTRIBUTES

        before_validation :apply_extended_api_journal_overrides_before_validation
        after_save :apply_extended_api_journal_overrides_after_save
        # before every other save callback: core's own (split_private_notes) and other plugins'
        before_save :skip_extended_api_journal, prepend: true
        after_save :keep_extended_api_journal_edit_metadata
      end

      private

      def allow_extended_api_overrides?(user)
        user.respond_to?(:admin?) && user.admin?
      end

      # skip_journal (admin only, see ApiHelpers): no journal is stored while the request's flag
      # is set. A callback, not an override of Issue#create_journal, create_parent_issue_journal
      # or IssueRelation#init_journals (see IssuePatch): each of them ends in Journal#save, which
      # returns false here and is not checked by core.
      def skip_extended_api_journal
        throw :abort if new_record? && Thread.current[:redmine_extended_api_skip_journal]
      end

      # skip_journal on PUT /extended_api/journals/:id: the notes change, the journal is not
      # marked as edited (updated_on, updated_by as before).
      def keep_extended_api_journal_edit_metadata
        return unless Thread.current[:redmine_extended_api_skip_journal]
        return if saved_change_to_id?

        cols = {}
        cols[:updated_on] = updated_on_before_last_save if saved_change_to_updated_on?
        cols[:updated_by_id] = updated_by_id_before_last_save if saved_change_to_updated_by_id?
        return if cols.empty?

        update_columns(cols)
      end

      def extended_api_journal_override_target?
        target_id = Thread.current[:redmine_extended_api_issue_target_id]
        target_id.present? && journalized_type.to_s == 'Issue' && journalized_id.to_s == target_id.to_s
      end

      # Pre-save: set imported values on the new journal
      def apply_extended_api_journal_overrides_before_validation
        return unless new_record? && extended_api_journal_override_target?

        overrides = Thread.current[:redmine_extended_api_journal_overrides]
        return unless overrides.is_a?(Hash)
        return unless allow_extended_api_overrides?(User.current)

        permitted = overrides.slice(*self.class.extended_api_journal_override_attributes).compact
        assign_attributes(permitted) unless permitted.empty?
      end

      def apply_extended_api_journal_overrides_after_save
        return if Thread.current[:redmine_extended_api_applying_journal_overrides]
        return unless saved_change_to_id? && extended_api_journal_override_target?

        overrides = Thread.current[:redmine_extended_api_journal_overrides]
        return unless overrides.is_a?(Hash)
        return unless allow_extended_api_overrides?(User.current)

        permitted = overrides.slice(*self.class.extended_api_journal_override_attributes).compact
        return if permitted.empty?

        cols = {}

        if permitted.key?(:user_id) && permitted[:user_id].present?
          cols[:user_id] = permitted[:user_id]
        end

        if permitted.key?(:updated_by_id) && permitted[:updated_by_id].present?
          cols[:updated_by_id] = permitted[:updated_by_id]
        end

        if permitted.key?(:created_on) && permitted[:created_on].present?
          cols[:created_on] = parse_extended_api_time(permitted[:created_on])
        end

        if permitted.key?(:updated_on) && permitted[:updated_on].present?
          cols[:updated_on] = parse_extended_api_time(permitted[:updated_on])
        end

        return if cols.empty?

        Thread.current[:redmine_extended_api_applying_journal_overrides] = true
        update_columns(cols)
        assign_attributes(cols)
      ensure
        Thread.current[:redmine_extended_api_applying_journal_overrides] = nil
      end
    end
  end
end

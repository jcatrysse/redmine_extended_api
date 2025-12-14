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

      included do
        class_attribute :extended_api_issue_override_attributes, instance_accessor: false
        self.extended_api_issue_override_attributes ||= ISSUE_OVERRIDE_ATTRIBUTES

        unless method_defined?(:safe_attributes_without_extended_api=)
          alias_method :safe_attributes_without_extended_api=, :safe_attributes=
          alias_method :safe_attributes=, :safe_attributes_with_extended_api=
        end

        unless method_defined?(:init_journal_without_extended_api)
          alias_method :init_journal_without_extended_api, :init_journal
          alias_method :init_journal, :init_journal_with_extended_api
        end

        after_save :apply_extended_api_issue_overrides_after_save
      end

      def safe_attributes_with_extended_api=(attrs, user = (defined?(User) ? User.current : nil))
        send(:safe_attributes_without_extended_api=, attrs, user)
        apply_extended_api_issue_overrides(user)
      end

      def init_journal_with_extended_api(user, notes = '')
        init_journal_without_extended_api(user, notes).tap do |journal|
          apply_extended_api_journal_overrides_on_init(journal, user)
        end
      end

      private

      def allow_extended_api_overrides?(user)
        user.respond_to?(:admin?) && user.admin?
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
        update_columns(cols)
        assign_attributes(cols)
      ensure
        Thread.current[:redmine_extended_api_applying_issue_overrides] = nil
      end
    end
  end
end

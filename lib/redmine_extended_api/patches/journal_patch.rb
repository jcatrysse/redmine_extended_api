# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/hash/slice'

module RedmineExtendedApi
  module Patches
    module JournalPatch
      extend ActiveSupport::Concern
      include ApiHelpers

      EXTENDED_API_JOURNAL_OVERRIDE_ATTRIBUTES = %i[user_id created_on updated_on updated_by_id].freeze

      included do
        class_attribute :extended_api_journal_override_attributes, instance_accessor: false
        self.extended_api_journal_override_attributes ||= EXTENDED_API_JOURNAL_OVERRIDE_ATTRIBUTES

        after_save :apply_extended_api_journal_overrides_after_save
      end

      private

      def allow_extended_api_overrides?(user)
        user.respond_to?(:admin?) && user.admin?
      end

      def apply_extended_api_journal_overrides_after_save
        return if Thread.current[:redmine_extended_api_applying_journal_overrides]

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

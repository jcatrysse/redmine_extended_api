# frozen_string_literal: true

require 'active_support/concern'
require 'active_support/core_ext/hash/slice'
require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module AttachmentPatch
      extend ActiveSupport::Concern
      include ApiHelpers

      EXTENDED_API_ATTACHMENT_OVERRIDE_ATTRIBUTES = %i[author_id created_on].freeze

      included do
        class_attribute :extended_api_attachment_override_attributes, instance_accessor: false
        self.extended_api_attachment_override_attributes ||= EXTENDED_API_ATTACHMENT_OVERRIDE_ATTRIBUTES

        if method_defined?(:safe_attributes=)
          unless method_defined?(:safe_attributes_without_extended_api_attachment=)
            alias_method :safe_attributes_without_extended_api_attachment=, :safe_attributes=
            alias_method :safe_attributes=, :safe_attributes_with_extended_api_attachment=
          end
        end

        before_validation :apply_extended_api_attachment_overrides_callback if respond_to?(:before_validation)
        after_save :apply_extended_api_attachment_overrides_after_save if respond_to?(:after_save)
      end

      def safe_attributes_with_extended_api_attachment=(attrs, user = (defined?(User) ? User.current : nil))
        send(:safe_attributes_without_extended_api_attachment=, attrs, user)
        apply_extended_api_attachment_overrides(user)
      end

      private

      def apply_extended_api_attachment_overrides_callback
        apply_extended_api_attachment_overrides(defined?(User) ? User.current : nil)
      end

      def apply_extended_api_attachment_overrides(user)
        overrides = Thread.current[:redmine_extended_api_attachment_overrides]
        return unless overrides.is_a?(Hash)
        return unless allow_extended_api_overrides?(user)

        permitted = overrides.slice(*self.class.extended_api_attachment_override_attributes).compact
        return if permitted.empty?

        assign_attributes(permitted) if respond_to?(:assign_attributes)
      end

      def allow_extended_api_overrides?(user)
        user.respond_to?(:admin?) && user.admin?
      end

      def apply_extended_api_attachment_overrides_after_save
        return if Thread.current[:redmine_extended_api_applying_attachment_overrides]

        overrides = Thread.current[:redmine_extended_api_attachment_overrides]
        return unless overrides.is_a?(Hash)
        return unless allow_extended_api_overrides?(defined?(User) ? User.current : nil)

        cols = {}

        if overrides.key?(:author_id) && overrides[:author_id].present?
          cols[:author_id] = overrides[:author_id]
        end

        if overrides.key?(:created_on) && overrides[:created_on].present?
          cols[:created_on] = parse_extended_api_time(overrides[:created_on])
        end

        return if cols.empty?

        Thread.current[:redmine_extended_api_applying_attachment_overrides] = true
        update_columns(cols)
        assign_attributes(cols) if respond_to?(:assign_attributes)
      ensure
        Thread.current[:redmine_extended_api_applying_attachment_overrides] = nil
      end
    end
  end
end

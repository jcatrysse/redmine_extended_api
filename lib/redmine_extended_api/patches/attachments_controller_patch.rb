# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module AttachmentsControllerPatch
      include ApiHelpers

      ATTACHMENT_OVERRIDE_KEYS = %i[author_id created_on].freeze

      def upload
        return super unless extended_api_request?

        previous_overrides = Thread.current[:redmine_extended_api_attachment_overrides]
        overrides = extract_attachment_override_attributes
        Thread.current[:redmine_extended_api_attachment_overrides] =
          allow_extended_api_attachment_overrides? ? overrides : {}

        super
      ensure
        Thread.current[:redmine_extended_api_attachment_overrides] = previous_overrides
      end

      private

      def extract_attachment_override_attributes
        nested = params[:attachment]
        return {} unless nested.respond_to?(:to_h)

        raw = if nested.respond_to?(:to_unsafe_h)
                nested.to_unsafe_h
              else
                nested.to_h
              end

        raw
          .transform_keys { |k| k.to_sym rescue k }
          .slice(*ATTACHMENT_OVERRIDE_KEYS)
          .compact
      rescue StandardError
        {}
      end

      def allow_extended_api_attachment_overrides?
        user = if respond_to?(:current_user, true)
                 current_user
               elsif defined?(User) && User.respond_to?(:current)
                 User.current
               end

        user.respond_to?(:admin?) && user.admin?
      end
    end
  end
end

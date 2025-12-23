# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module IssueRelationsControllerPatch
      include ApiHelpers

      def create
        return super unless extended_api_request?

        with_extended_api_relation_context { super }
      end

      def destroy
        return super unless extended_api_request?

        with_extended_api_relation_context { super }
      end

      private

      def with_extended_api_relation_context
        # Preserve existing suppression state to allow nested notification guards.
        previous_suppression = Thread.current[:redmine_extended_api_suppress_notifications]
        suppress_notifications = suppress_relation_notifications?

        Thread.current[:redmine_extended_api_suppress_notifications] = true if suppress_notifications

        if suppress_notifications && defined?(Mailer)
          Mailer.with_deliveries(false) { yield }
        else
          yield
        end
      ensure
        Thread.current[:redmine_extended_api_suppress_notifications] = previous_suppression
      end

      def suppress_relation_notifications?
        extended_api_suppress_notifications?(params)
      end
    end
  end
end

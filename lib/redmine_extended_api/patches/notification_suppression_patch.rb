# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    # Included in Issue and Journal; send_notification is not overridden. Prepending it recursed
    # next to a plugin that alias_method-chains it later (Redmine 5.1/6.1), alias_method next to
    # one that prepends it (redmine_stealth). Core's send_notification (after_create_commit) does
    # nothing when notify? is false, so the records saved while the request's flag is set get
    # notify = false before they are saved.
    module NotificationSuppressionPatch
      def self.included(base)
        base.before_save :apply_extended_api_notification_suppression
      end

      private

      def apply_extended_api_notification_suppression
        self.notify = false if Thread.current[:redmine_extended_api_suppress_notifications]
        nil
      end
    end
  end
end

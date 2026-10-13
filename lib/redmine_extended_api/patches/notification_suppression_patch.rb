# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    # Prepended, not alias_method: other plugins (redmine_stealth) prepend send_notification
    # on Issue and Journal too, and an alias_method chain on a prepended method recurses.
    module NotificationSuppressionPatch
      private

      def send_notification(*args)
        return if Thread.current[:redmine_extended_api_suppress_notifications]

        super
      end
    end
  end
end

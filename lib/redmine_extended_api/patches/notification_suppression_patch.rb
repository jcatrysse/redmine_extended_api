# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    module NotificationSuppressionPatch
      def self.included(base)
        base.class_eval do
          next unless
            method_defined?(:send_notification) ||
            private_method_defined?(:send_notification) ||
            protected_method_defined?(:send_notification)

          visibility = if private_method_defined?(:send_notification)
                          :private
                        elsif protected_method_defined?(:send_notification)
                          :protected
                        else
                          :public
                        end

          alias_method :send_notification_without_extended_api, :send_notification
          alias_method :send_notification, :send_notification_with_extended_api
          send(visibility, :send_notification)
        end
      end

      def send_notification_with_extended_api(*args)
        return if Thread.current[:redmine_extended_api_suppress_notifications]
        send_notification_without_extended_api(*args)
      end
    end
  end
end

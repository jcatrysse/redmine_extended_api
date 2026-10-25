# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    # Decision of Jan, 2026-10-07: notify=false (or send_notification=0) on /extended_api
    # also silences the Redmine 7 webhooks of that request, so an import stays invisible to
    # connected systems. Prepended on Webhook's singleton class; the flag is the thread-local
    # one the issue and relation patches set for the duration of the request.
    module WebhookPatch
      def trigger(event, object)
        return if Thread.current[:redmine_extended_api_suppress_notifications]

        super
      end
    end
  end
end

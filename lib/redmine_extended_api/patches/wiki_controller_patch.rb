# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    # SPR-525: a wiki page written through /extended_api with notify=false sends no mail.
    # A bulk import (Markdown, a Confluence space) writes dozens of pages in a row; with
    # wiki_content_added/updated among the notified events every one of them mailed every
    # member of the project. The flag is the request thread's, like for issues; the mail is
    # stopped where WikiContent sends it (WikiContentNotificationPatch), because core's
    # Mailer.deliver_wiki_content_* deliver later — outside the request thread.
    #
    # The flag is read from the query (?notify=false) or from wiki_page[notify]; the core
    # route (/projects/...) ignores it, as it does for issues.
    module WikiControllerPatch
      include ApiHelpers

      def update
        return super unless extended_api_request?

        with_extended_api_wiki_notifications { super }
      end

      private

      def with_extended_api_wiki_notifications
        previous_suppression = Thread.current[:redmine_extended_api_suppress_notifications]
        Thread.current[:redmine_extended_api_suppress_notifications] = true if suppress_wiki_notifications?

        yield
      ensure
        Thread.current[:redmine_extended_api_suppress_notifications] = previous_suppression
      end

      def suppress_wiki_notifications?
        return true if extended_api_suppress_notifications?(params)

        page_params = params[:wiki_page]
        page_params.respond_to?(:key?) && extended_api_suppress_notifications?(page_params)
      end
    end

    # SPR-525: WikiContent mails from its after_commit callbacks, which run inside the
    # request (the transaction commits there); while the request's flag is set they send
    # nothing. Webhooks (Redmine 7) are held back by WebhookPatch on the same flag.
    module WikiContentNotificationPatch
      private

      def send_notification_create
        return if Thread.current[:redmine_extended_api_suppress_notifications]

        super
      end

      def send_notification_update
        return if Thread.current[:redmine_extended_api_suppress_notifications]

        super
      end
    end
  end
end

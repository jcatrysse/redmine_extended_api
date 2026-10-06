# frozen_string_literal: true

module RedmineExtendedApi
  # Drops mail delivered in the thread of an /extended_api request made with notify=false
  # (deliver_now, or jobs run inline). Thread-local on purpose: Mailer.with_deliveries(false),
  # used before, switched deliveries off for the whole process, so mail of other requests and
  # of async mail jobs delivered meanwhile was lost.
  module MailSuppressionInterceptor
    def self.delivering_email(message)
      message.perform_deliveries = false if Thread.current[:redmine_extended_api_suppress_notifications]
    end
  end
end

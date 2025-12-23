# frozen_string_literal: true

require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/hash/keys'
require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module IssuesControllerPatch
      def self.prepended(base)
        # Zorg dat de view de metadata methode kan vinden
        base.send(:helper_method, :extended_api_metadata) if base.respond_to?(:helper_method)
      end
      include ApiHelpers

      ISSUE_OVERRIDE_KEYS = %i[author_id created_on updated_on closed_on].freeze
      JOURNAL_OVERRIDE_KEYS = %i[user_id created_on updated_on updated_by_id].freeze

      def create
        return super unless extended_api_request?

        with_extended_api_issue_context { super }
      end

      def update
        return super unless extended_api_request?

        with_extended_api_issue_context { super }
      end

      def render_api_ok(*args)
        if extended_api_request? && api_request? && action_name == 'update'
          journal = extended_api_journal_for_response
          if journal
            @journal = journal
            return render_extended_api('journals/show')
          end
        end

        super
      end

      private

      def with_extended_api_issue_context
        previous_overrides = Thread.current[:redmine_extended_api_issue_overrides]
        previous_journal_overrides = Thread.current[:redmine_extended_api_journal_overrides]
        previous_issue_record_timestamps = Issue.record_timestamps if defined?(Issue) && Issue.respond_to?(:record_timestamps)
        disable_issue_timestamps = false
        overrides_allowed = allow_extended_api_overrides?

        overrides = extract_issue_override_attributes
        Thread.current[:redmine_extended_api_issue_overrides] = overrides if overrides_allowed

        disable_issue_timestamps = overrides_allowed && should_skip_issue_timestamps?(overrides)
        Issue.record_timestamps = false if disable_issue_timestamps

        journal_overrides = extract_journal_override_attributes
        Thread.current[:redmine_extended_api_journal_overrides] = journal_overrides if overrides_allowed

        suppress_notifications = suppress_issue_notifications?

        if suppress_notifications
          Thread.current[:redmine_extended_api_suppress_notifications] = true
        end

        if suppress_notifications && defined?(Mailer)
          Mailer.with_deliveries(false) { yield }
        else
          yield
        end

      ensure
        Thread.current[:redmine_extended_api_issue_overrides] = previous_overrides
        Thread.current[:redmine_extended_api_journal_overrides] = previous_journal_overrides
        Thread.current[:redmine_extended_api_suppress_notifications] = nil
        if disable_issue_timestamps && defined?(Issue) && Issue.respond_to?(:record_timestamps=)
          Issue.record_timestamps = previous_issue_record_timestamps
        end
      end

      def allow_extended_api_overrides?
        return false unless defined?(User) && User.respond_to?(:current)

        user = User.current
        user.respond_to?(:admin?) && user.admin?
      end

      def extract_issue_override_attributes
        return {} unless params[:issue].respond_to?(:to_h)

        raw_hash = if params[:issue].respond_to?(:to_unsafe_h)
                     params[:issue].to_unsafe_h
                   else
                     params[:issue].to_h
                   end

        raw_hash.transform_keys { |key| key.to_sym rescue key }.slice(*ISSUE_OVERRIDE_KEYS).compact
      rescue StandardError
        {}
      end

      def should_skip_issue_timestamps?(overrides)
        return false unless defined?(Issue) && Issue.respond_to?(:record_timestamps=)

        overrides.key?(:created_on) || overrides.key?(:updated_on)
      end

      def should_skip_journal_timestamps?(overrides)
        return false unless defined?(Journal) && Journal.respond_to?(:record_timestamps=)

        overrides.key?(:created_on) || overrides.key?(:updated_on)
      end

      def extract_journal_override_attributes
        candidates = []

        if params[:journal].respond_to?(:to_unsafe_h)
          candidates << params[:journal].to_unsafe_h
        elsif params[:journal].respond_to?(:to_h)
          candidates << params[:journal].to_h
        end

        issue_hash = nil

        if params[:issue].respond_to?(:to_unsafe_h)
          issue_hash = params[:issue].to_unsafe_h
        elsif params[:issue].respond_to?(:to_h)
          issue_hash = params[:issue].to_h
        end

        if issue_hash.is_a?(Hash)
          nested = issue_hash[:journal] || issue_hash['journal']

          if nested.respond_to?(:to_unsafe_h)
            candidates << nested.to_unsafe_h
          elsif nested.respond_to?(:to_h)
            candidates << nested.to_h
          end
        end

        candidates.each do |raw|
          transformed = safe_transform_and_slice(raw)
          return transformed unless transformed.empty?
        end

        {}
      rescue StandardError
        {}
      end

      def safe_transform_and_slice(raw_hash)
        hash = if raw_hash.respond_to?(:to_unsafe_h)
                 raw_hash.to_unsafe_h
               else
                 raw_hash.to_h
               end

        hash.transform_keys { |key| key.to_sym rescue key }.slice(*JOURNAL_OVERRIDE_KEYS).compact
      end

      def suppress_issue_notifications?
        extended_api_suppress_notifications?(params)
      end

      def extended_api_journal_for_response
        return unless defined?(@issue) && @issue

        if @issue.respond_to?(:current_journal) && @issue.current_journal
          return @issue.current_journal
        end

        return unless @issue.respond_to?(:journals)

        @issue.journals.order(:id).last
      rescue StandardError
        nil
      end
    end
  end
end

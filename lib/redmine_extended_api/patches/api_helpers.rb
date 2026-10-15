# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    module ApiHelpers
      EXTENDED_API_TIME_OVERRIDE_KEYS = %i[created_on updated_on closed_on].freeze
      EXTENDED_API_USER_OVERRIDE_KEYS = %i[author_id user_id updated_by_id].freeze

      def self.included(base)
        super
        base.helper_method(:extended_api_metadata) if base.respond_to?(:helper_method)
      end

      private

      def render_extended_api(template, status: :ok, location: nil)
        mark_extended_api_response(fallback: false)

        respond_to do |format|
          format.api do
            options = {template: "redmine_extended_api/#{template}", status: status}
            options[:location] = location if location
            render options
          end
        end
      end

      def api_request_format_symbol(default = nil)
        format = if respond_to?(:request, true)
                   req = request
                   req.format if req && req.respond_to?(:format)
                 end

        symbol = if format.respond_to?(:symbol)
                   format.symbol
                 elsif format.respond_to?(:to_sym)
                   format.to_sym
                 end

        symbol ||= params[:format].to_sym if respond_to?(:params, true) && params && params[:format]

        symbol || default
      rescue StandardError
        default
      end

      def extended_api_request?
        return false unless api_request?

        req = request if respond_to?(:request, true)
        return false unless req

        env = req.respond_to?(:env) ? req.env : nil
        return false unless env.is_a?(Hash)

        original_path = env.fetch('redmine_extended_api.original_path_info', nil)
        original_script_name = env.fetch('redmine_extended_api.original_script_name', nil)

        return true if path_prefixed_with_extended_api?(original_path)

        combined = String(original_script_name) + String(original_path)
        path_prefixed_with_extended_api?(combined)
      end

      def render_api_validation_errors(record)
        mark_extended_api_response(fallback: false)

        respond_to do |format|
          format.api {render_validation_errors(record)}
        end
      end

      def render_api_error_message(message, status: 422)
        mark_extended_api_response(fallback: false)

        respond_to do |format|
          # Not render_error: it answers API formats with an empty body, so the reason was lost.
          # This is core's render_api_errors with a status.
          format.api do
            @error_messages = Array(message)
            render template: 'common/error_messages', format: [:api], status: status, layout: nil
          end
        end
      end

      def render_api_not_found(message = nil)
        default_message = I18n.t(:notice_file_not_found, default: 'Not found')

        mark_extended_api_response(fallback: false)

        respond_to do |format|
          format.api do
            render_error(message: message || default_message, status: :not_found)
          end
        end
      end

      def path_prefixed_with_extended_api?(value)
        value.to_s.include?(RedmineExtendedApi::API_PREFIX)
      end

      def extended_api_metadata
        @extended_api_metadata || {mode: 'native', fallback_to_native: true}
      end

      def mark_extended_api_response(fallback:)
        metadata = {
          mode: fallback ? 'native' : 'extended',
          fallback_to_native: fallback
        }

        @extended_api_metadata = metadata

        return unless respond_to?(:response, true)

        resp = response
        return unless resp

        header_value = metadata[:mode]

        if resp.respond_to?(:set_header)
          resp.set_header('X-Redmine-Extended-API', header_value)
        elsif resp.respond_to?(:headers)
          headers = resp.headers || {}
          headers['X-Redmine-Extended-API'] = header_value
          resp.headers = headers if resp.respond_to?(:headers=)
        end
      end

      # Messages for override values that cannot be stored: a time that does not parse or a user
      # id that is no user. They used to be saved as NULL or as a dangling id, which failed later
      # in mails, webhooks and journals.
      def extended_api_override_errors(overrides)
        overrides.filter_map do |key, value|
          next if value.blank?

          # the overrides come from params, a hash with indifferent access and string keys
          key = key.to_sym

          if EXTENDED_API_TIME_OVERRIDE_KEYS.include?(key)
            next if parse_extended_api_time(value)
          elsif EXTENDED_API_USER_OVERRIDE_KEYS.include?(key)
            next if extended_api_user_exists?(value)
          else
            next
          end

          label = I18n.t(:"field_#{key.to_s.delete_suffix('_id')}", default: key.to_s.humanize)
          "#{label} #{I18n.t('activerecord.errors.messages.invalid', default: 'is invalid')}"
        end
      end

      def extended_api_user_exists?(value)
        value.to_s.match?(/\A\d+\z/) && User.where(id: value.to_i).exists?
      end

      def parse_extended_api_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        Time.zone.parse(value.to_s)
      rescue StandardError
        nil
      end

      # skip_journal (decision 37 of the Jira migration, 2026-10-15): an admin's import
      # post-processing on /extended_api leaves no journal (issue update, "Subtask added" on the
      # parent, relation journals) and no edit trace (updated_on of the issues it saves, updated_on
      # and updated_by of a journal it rewrites). Same values as notify, the other way round.
      def extended_api_skip_journal_requested?
        return false unless respond_to?(:params, true) && params

        value = params[:skip_journal]
        value == true || %w[true 1 on yes].include?(value.to_s.strip.downcase)
      end

      def extended_api_skip_journal_allowed?
        User.current.respond_to?(:admin?) && User.current.admin?
      end

      # A non-admin asking for skip_journal is refused (403) instead of getting journals it asked
      # not to write.
      def render_refused_extended_api_skip_journal
        return false unless extended_api_skip_journal_requested?
        return false if extended_api_skip_journal_allowed?

        render_api_error_message(I18n.t(:notice_not_authorized), status: 403)
        true
      end

      # Sets the request's skip_journal flag for the block; read by IssuePatch and JournalPatch.
      def with_extended_api_skip_journal
        previous = Thread.current[:redmine_extended_api_skip_journal]
        if extended_api_skip_journal_requested? && extended_api_skip_journal_allowed?
          Thread.current[:redmine_extended_api_skip_journal] = true
        end

        yield
      ensure
        Thread.current[:redmine_extended_api_skip_journal] = previous
      end

      def extended_api_suppress_notifications?(params_hash)
        return false unless params_hash

        keys = %w[notify notifications send_notification send_notifications]
        key = keys.find { |k| params_hash.key?(k) || params_hash.key?(k.to_sym) }
        return false unless key

        value = params_hash[key] || params_hash[key.to_sym]

        return true if value == false
        %w[false 0 off no].include?(value.to_s.strip.downcase)
      end
    end
  end
end

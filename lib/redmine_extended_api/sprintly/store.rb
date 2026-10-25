# frozen_string_literal: true

require 'json'

module RedmineExtendedApi
  module Sprintly
    # SPR-383: who holds which Sprintly role, kept by the server.
    #
    # The roles themselves are Redmine roles. What Redmine has no place for lives here, as one
    # JSON document in this plugin's settings (no migration needed, so a plain image rebuild
    # deploys it):
    #
    #   {
    #     "version": 1,
    #     "users":    { "<user id>":  [role ids] },     global role of a user
    #     "groups":   { "<group id>": [role ids] },     global role of a group
    #     "default_role_id": <role id or null>,         for whoever has no role of their own
    #     "projects": { "<project id>": { "users": {...}, "groups": {...} } },  per-project overrides
    #     "roles":    { "<role id>": { "description": "...", "preset": "admin" } },
    #     "company_icon": ...                            carried over from the old SPA config
    #   }
    #
    # Until this document exists the plugin enforces nothing new: the server behaves exactly
    # as before, and the SPA keeps reading its roles from `welcome_text`. Creating it (the
    # import) is what switches the tenant over.
    module Store
      SETTING_NAME = 'plugin_redmine_extended_api'
      KEY = 'sprintly_access'
      VERSION = 1

      module_function

      def initialized?
        read.present?
      end

      # A fresh copy every call, so callers may mutate what they get.
      def read
        raw = settings_hash[KEY]
        return nil if raw.blank?

        data = raw.is_a?(String) ? JSON.parse(raw) : raw.to_h.deep_stringify_keys
        normalize(data)
      rescue JSON::ParserError
        nil
      end

      def blank_document
        normalize({})
      end

      # Read-modify-write under a row lock on the setting, so two admins saving at once do not
      # drop each other's change (the bug the old `welcome_text` storage had by design).
      def update!
        Setting.transaction do
          Setting.where(name: SETTING_NAME).lock.first
          data = read || blank_document
          result = yield data
          write!(data)
          result
        end
      end

      def write!(data)
        settings = settings_hash.dup
        settings[KEY] = JSON.generate(normalize(data))
        Setting.send(:"#{SETTING_NAME}=", settings)
      end

      def clear!
        settings = settings_hash.dup
        settings.delete(KEY)
        Setting.send(:"#{SETTING_NAME}=", settings)
      end

      def settings_hash
        value = Setting.send(SETTING_NAME)
        value.respond_to?(:to_h) ? value.to_h.stringify_keys : {}
      rescue StandardError
        {}
      end

      def normalize(data)
        data = data.to_h.deep_stringify_keys
        {
          'version' => VERSION,
          'users' => id_lists(data['users']),
          'groups' => id_lists(data['groups']),
          'default_role_id' => data['default_role_id'].presence&.to_i,
          'projects' => (data['projects'] || {}).to_h.each_with_object({}) do |(pid, scope), out|
            scope = scope.to_h
            entry = { 'users' => id_lists(scope['users']), 'groups' => id_lists(scope['groups']) }
            out[pid.to_s] = entry if entry['users'].any? || entry['groups'].any?
          end,
          'roles' => (data['roles'] || {}).to_h.transform_keys(&:to_s).transform_values { |v| v.to_h.slice('description', 'preset') },
          'company_icon' => data['company_icon'],
          'imported_at' => data['imported_at'],
          'builtin_backup' => data['builtin_backup']
        }.compact
      end

      def id_lists(hash)
        (hash || {}).to_h.each_with_object({}) do |(key, ids), out|
          list = Array(ids).map(&:to_i).reject(&:zero?).uniq
          out[key.to_s] = list if list.any?
        end
      end
    end
  end
end

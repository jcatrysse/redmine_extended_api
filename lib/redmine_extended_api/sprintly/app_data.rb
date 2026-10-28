# frozen_string_literal: true

require 'digest'
require 'json'

module RedmineExtendedApi
  module Sprintly
    # SPR-553: the SPA's personal store — the user custom field "App data", one JSON object
    # per user (dashboards, saved filters; see tracker-ui `AppDataStoreService`).
    #
    # Redmine has no owner-only visibility for user fields: a `visible` field is shown to
    # everybody in `/users/:id.json` (and `/users.json`), a hidden one to nobody — not even
    # its owner in `/my/account.json`. So the value is read and written here, through
    # `/sprintly/me/app_data`, whatever the field's `visible` flag says, and `UserPatch` drops it
    # from every other user's view of the account, administrators included.
    module AppData
      FIELD_NAME = 'App data'
      FIELD_DESCRIPTION = 'Managed by the web app (saved filters and other personal settings) as JSON. Do not edit or delete.'
      # A `text` column holds 65 535 bytes on MySQL; the SPA keeps itself under 60 000.
      MAX_BYTES = 65_000

      class ConflictError < StandardError; end
      class InvalidValueError < StandardError; end

      module_function

      def field?(field)
        field.is_a?(UserCustomField) && field.name == FIELD_NAME
      end

      def fields
        UserCustomField.where(name: FIELD_NAME, field_format: 'text').order(:id).to_a
      end

      # The user's value and the field it is kept in. Should two fields of that name exist
      # (created at the same moment), the one holding the user's data wins, as in the SPA.
      def read(user)
        candidates = fields
        return [nil, nil] if candidates.empty?

        values = CustomValue.where(customized: user, custom_field_id: candidates.map(&:id)).to_a
        held = values.find { |cv| cv.value.present? }
        return [held.value, candidates.find { |f| f.id == held.custom_field_id }] if held

        [nil, candidates.first]
      end

      # Identifies a stored value for optimistic locking: the client sends back the digest it
      # read, and a write over a value that has changed since is refused.
      def digest(value)
        Digest::SHA256.hexdigest(value.to_s)
      end

      # Replaces the user's whole value. Read-modify-write under a row lock on the user, so a
      # write from another device in between is caught (when `expected_digest` is given)
      # rather than silently overwritten. Creates the field on the first write.
      def write!(user, value, expected_digest = nil)
        validate!(value)
        User.transaction do
          User.lock.where(id: user.id).first
          current, field = read(user)
          raise ConflictError, 'app data changed since it was read' if expected_digest && expected_digest != digest(current)

          field ||= ensure_field!
          stored = CustomValue.where(customized: user, custom_field_id: field.id).order(:id).first ||
                   CustomValue.new(customized: user, custom_field: field)
          stored.value = value
          stored.save!
          value
        end
      end

      def validate!(value)
        raise InvalidValueError, 'value must be a string holding a JSON object' unless value.is_a?(String)
        raise InvalidValueError, "value is larger than #{MAX_BYTES} bytes" if value.bytesize > MAX_BYTES

        parsed = JSON.parse(value)
        raise InvalidValueError, 'value must be a JSON object' unless parsed.is_a?(Hash)
      rescue JSON::ParserError
        raise InvalidValueError, 'value must be a JSON object'
      end

      # The same field the SPA used to create itself (administrators only); any user may get
      # it created here, since it only ever holds their own data. Left `visible` so that a SPA
      # still reading `/my/account.json` keeps working — `UserPatch` is what keeps it private.
      def ensure_field!
        fields.first || UserCustomField.create!(
          name: FIELD_NAME, description: FIELD_DESCRIPTION, field_format: 'text', text_formatting: '',
          is_required: false, is_filter: false, searchable: false, visible: true, editable: true
        )
      rescue ActiveRecord::RecordInvalid
        # Created by another request a moment ago (names are unique per type).
        fields.first || raise
      end

      module UserPatch
        # `/users/:id.json`, `/users.json`, `/my/account.json` and the profile page show these.
        # The owner keeps seeing the value; nobody else does, whatever the field's flag.
        def visible_custom_field_values(*args)
          values = super
          return values if User.current.logged? && User.current.id == id

          values.reject { |custom_value| AppData.field?(custom_value.custom_field) }
        end
      end
    end
  end
end

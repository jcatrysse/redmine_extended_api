# frozen_string_literal: true

require 'set'

module RedmineExtendedApi
  module CustomFields
    # Determines which attributes are relevant for a given custom field based on
    # its type (IssueCustomField, UserCustomField, ...) and the selected field
    # format (string, list, depending_list, ...). The policy is used to both
    # filter incoming parameters for create/update requests and to decide which
    # attributes should be rendered by the API responses.
    class AttributePolicy
      FILTERABLE_TYPES = %w[
        IssueCustomField
        UserCustomField
        ProjectCustomField
        VersionCustomField
        GroupCustomField
        TimeEntryCustomField
        TimeEntryActivityCustomField
        DocumentCategoryCustomField
      ].freeze

      SEARCHABLE_TYPES = %w[
        IssueCustomField
        ProjectCustomField
      ].freeze

      ROLE_TYPES = %w[
        IssueCustomField
        TimeEntryCustomField
        ProjectCustomField
        VersionCustomField
      ].freeze

      TRACKER_TYPES = %w[IssueCustomField].freeze
      PROJECT_TYPES = %w[IssueCustomField].freeze
      USER_TYPES = %w[UserCustomField].freeze

      BASE_DISPLAY_ATTRIBUTES = %i[
        id
        name
        description
        type
        field_format
        is_required
        position
      ].freeze

      BASE_ASSIGNABLE_ATTRIBUTES = %i[
        name
        description
        field_format
        is_required
        position
      ].freeze

      BOOLEAN_ATTRIBUTES = %i[
        is_required
        is_for_all
        is_filter
        searchable
        visible
        editable
        multiple
        thousands_delimiter
        full_width_layout
        hide_when_disabled
        exclude_admins
        show_active
        show_registered
        show_locked
      ].freeze

      BOOLEAN_TYPE = if defined?(ActiveModel::Type::Boolean)
                       ActiveModel::Type::Boolean.new
                     end

      def initialize(custom_field)
        @custom_field = custom_field
        @format = custom_field.format
      end

      def display_attribute?(attribute)
        display_attributes.include?(attribute.to_sym)
      end

      def assignable_attributes
        @assignable_attributes ||= begin
          attrs = Set.new(BASE_ASSIGNABLE_ATTRIBUTES)
          attrs.merge(format_assignable_attributes)
          attrs.merge(type_assignable_attributes)
          attrs << :multiple if format_supports_multiple?
          attrs << :is_filter if filter_supported?
          attrs << :searchable if searchable_supported?
          attrs << :visible if user_type?
          attrs << :editable if user_type?
          attrs << :is_for_all if issue_type?
          attrs.to_a
        end
      end

      def boolean_value(attribute, value)
        return value unless BOOLEAN_ATTRIBUTES.include?(attribute.to_sym)

        if BOOLEAN_TYPE
          BOOLEAN_TYPE.cast(value)
        else
          %w[true 1].include?(value.to_s)
        end
      end

      private

      attr_reader :custom_field, :format

      def display_attributes
        @display_attributes ||= begin
          attrs = Set.new(BASE_DISPLAY_ATTRIBUTES)
          attrs << :customized_type if customized_type_available?
          attrs.merge(format_display_attributes)
          attrs.merge(type_display_attributes)
          attrs << :multiple if format_supports_multiple?
          attrs << :is_filter if filter_supported?
          attrs << :searchable if searchable_supported?
          attrs << :visible if user_type?
          attrs << :editable if user_type?
          attrs << :is_for_all if issue_type?
          attrs.to_a
        end
      end

      def customized_type_available?
        klass = custom_field.class
        return false unless klass.respond_to?(:customized_class)

        !!klass.customized_class
      end

      def type_display_attributes
        attrs = []
        attrs << :roles if role_type?
        attrs << :trackers if tracker_type?
        attrs << :projects if project_type?
        attrs
      end

      def type_assignable_attributes
        attrs = []
        attrs << :role_ids if role_type?
        attrs << :tracker_ids if tracker_type?
        attrs << :project_ids if project_type?
        attrs
      end

      def format_display_attributes
        case field_format
        when 'string'
          %i[regexp min_length max_length text_formatting default_value url_pattern]
        when 'text'
          attrs = %i[regexp min_length max_length text_formatting default_value]
          attrs << :full_width_layout if issue_type?
          attrs
        when 'link'
          %i[regexp min_length max_length url_pattern default_value]
        when 'int', 'float'
          %i[regexp min_length max_length default_value url_pattern thousands_delimiter]
        when 'date'
          %i[default_value url_pattern]
        when 'list'
          %i[possible_values default_value url_pattern edit_tag_style]
        when 'bool'
          %i[default_value url_pattern edit_tag_style]
        when 'enumeration'
          %i[default_value url_pattern edit_tag_style enumerations]
        when 'user'
          %i[user_role edit_tag_style]
        when 'version'
          %i[version_status edit_tag_style]
        when 'attachment'
          %i[extensions_allowed]
        when 'progressbar'
          %i[ratio_interval]
        else
          depending_format_display_attributes
        end
      end

      def format_assignable_attributes
        case field_format
        when 'string'
          %i[regexp min_length max_length text_formatting default_value url_pattern]
        when 'text'
          attrs = %i[regexp min_length max_length text_formatting default_value]
          attrs << :full_width_layout if issue_type?
          attrs
        when 'link'
          %i[regexp min_length max_length url_pattern default_value]
        when 'int', 'float'
          %i[regexp min_length max_length default_value url_pattern thousands_delimiter]
        when 'date'
          %i[default_value url_pattern]
        when 'list'
          %i[possible_values default_value url_pattern edit_tag_style]
        when 'bool'
          %i[default_value url_pattern edit_tag_style]
        when 'enumeration'
          %i[default_value url_pattern edit_tag_style]
        when 'user'
          %i[user_role edit_tag_style]
        when 'version'
          %i[version_status edit_tag_style]
        when 'attachment'
          %i[extensions_allowed]
        when 'progressbar'
          %i[ratio_interval]
        else
          depending_format_assignable_attributes
        end
      end

      def depending_format_display_attributes
        if depending_list_format?
          %i[
            possible_values
            default_value
            url_pattern
            edit_tag_style
            parent_custom_field_id
            value_dependencies
            default_value_dependencies
            hide_when_disabled
          ]
        elsif depending_enumeration_format?
          %i[
            default_value
            url_pattern
            edit_tag_style
            enumerations
            parent_custom_field_id
            value_dependencies
            default_value_dependencies
            hide_when_disabled
          ]
        elsif extended_user_format?
          %i[
            group_ids
            exclude_admins
            show_active
            show_registered
            show_locked
            edit_tag_style
          ]
        else
          []
        end
      end

      def depending_format_assignable_attributes
        if depending_list_format?
          %i[
            possible_values
            default_value
            url_pattern
            edit_tag_style
            parent_custom_field_id
            value_dependencies
            default_value_dependencies
            hide_when_disabled
          ]
        elsif depending_enumeration_format?
          %i[
            default_value
            url_pattern
            edit_tag_style
            parent_custom_field_id
            value_dependencies
            default_value_dependencies
            hide_when_disabled
          ]
        elsif extended_user_format?
          %i[
            group_ids
            exclude_admins
            show_active
            show_registered
            show_locked
            edit_tag_style
          ]
        else
          []
        end
      end

      def field_format
        custom_field.field_format.to_s
      end

      def custom_field_type
        custom_field.class.name.to_s
      end

      def filter_supported?
        FILTERABLE_TYPES.include?(custom_field_type) && format.is_filter_supported
      end

      def searchable_supported?
        SEARCHABLE_TYPES.include?(custom_field_type) && format.searchable_supported
      end

      def format_supports_multiple?
        format.multiple_supported
      end

      def issue_type?
        custom_field_type == 'IssueCustomField'
      end

      def user_type?
        USER_TYPES.include?(custom_field_type)
      end

      def role_type?
        ROLE_TYPES.include?(custom_field_type)
      end

      def tracker_type?
        TRACKER_TYPES.include?(custom_field_type)
      end

      def project_type?
        PROJECT_TYPES.include?(custom_field_type)
      end

      def depending_list_format?
        defined?(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST) &&
          field_format == RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST
      end

      def depending_enumeration_format?
        defined?(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION) &&
          field_format == RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
      end

      def extended_user_format?
        defined?(RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER) &&
          field_format == RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER
      end
    end
  end
end

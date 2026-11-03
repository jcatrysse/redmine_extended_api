# frozen_string_literal: true

require 'set'

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module CustomFieldsControllerPatch
      include ApiHelpers

      WRITE_ACTIONS = %i[create update destroy].freeze

      class << self
        # The write actions core's own paths take no API key for (core: accept_api_auth :index).
        attr_accessor :extended_api_only_actions
      end

      def self.prepended(base)
        core_actions = base.respond_to?(:accept_api_auth_actions) ? Array(base.accept_api_auth_actions) : []
        self.extended_api_only_actions = WRITE_ACTIONS - core_actions.map(&:to_sym)
        base.accept_api_auth :index, :show, :create, :update, :destroy
        base.helper_method :extended_api_metadata if base.respond_to?(:helper_method)
      end

      # The class list above must name the write actions, because ProxyApp only forwards actions
      # that take an API key. Core's own paths (/custom_fields.json, not through /extended_api) keep
      # core's API authentication: an API key there acted and then answered 302 or 406.
      def accept_api_auth?(action = action_name)
        if !extended_api_request? &&
           Array(CustomFieldsControllerPatch.extended_api_only_actions).include?(action.to_sym)
          return false
        end

        super
      end

      def show
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        @custom_field = CustomField.find(params[:id])
        render_extended_api('custom_fields/show')
      rescue ActiveRecord::RecordNotFound
        render_api_not_found
      end

      def create
        if !extended_api_request?
          return super if defined?(super)
          return render_404
        end

        enumeration_attrs = extract_enumerations_param(@custom_field)

        assign_filtered_attributes(@custom_field)

        if @custom_field.save
          apply_enumerations(@custom_field, enumeration_attrs)

          call_hook(
            :controller_custom_fields_new_after_save,
            params: params,
            custom_field: @custom_field
          )
          render_custom_field(status: :created)
        else
          render_api_validation_errors(@custom_field)
        end
      end

      def update
        if !extended_api_request?
          return super if defined?(super)
          return render_404
        end

        enumeration_attrs = extract_enumerations_param(@custom_field)

        assign_filtered_attributes(@custom_field)

        if @custom_field.save
          apply_enumerations(@custom_field, enumeration_attrs)

          call_hook(
            :controller_custom_fields_edit_after_save,
            params: params,
            custom_field: @custom_field
          )
          render_custom_field
        else
          render_api_validation_errors(@custom_field)
        end
      end

      def destroy
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        if @custom_field.destroy
          mark_extended_api_response(fallback: false)
          head :no_content
        else
          render_api_validation_errors(@custom_field)
        end
      rescue StandardError => e
        render_api_error_message(e.message)
      end

      def render_custom_field(status: :ok)
        render_extended_api(
          'custom_fields/show',
          status: status,
          location: custom_fields_url(format: api_request_format_symbol(:json))
        )
      end

      private

      # Core's before_action renders the HTML "select the type" page when params[:type] is
      # missing or unknown, which answered an API create with 200 and HTML.
      # Core also assigns every safe attribute of params[:custom_field] here, before create
      # filters them through the AttributePolicy; an extended create sets only the format the
      # policy depends on, and create assigns the filtered attributes.
      def build_new_custom_field
        return super unless extended_api_request?

        @custom_field = CustomField.new_subclass_instance(params[:type])
        if @custom_field.nil?
          return render_api_error_message(
            "#{I18n.t(:field_type)} #{I18n.t('activerecord.errors.messages.invalid')}"
          )
        end

        if params[:copy].present? && (@copy_from = CustomField.find_by(id: params[:copy]))
          @custom_field.copy_from(@copy_from)
        end
        field_format = raw_custom_field_params['field_format']
        @custom_field.field_format = field_format.to_s unless field_format.nil?
      end

      def assign_filtered_attributes(custom_field)
        attributes = filtered_custom_field_params(custom_field)
        return if attributes.empty?

        custom_field.safe_attributes = attributes
      end

      def raw_custom_field_params
        raw = params[:custom_field]
        # an Array (custom_field[]=...) has to_h too, and raised TypeError (500)
        return {} unless raw.is_a?(Hash) ||
                         (defined?(ActionController::Parameters) && raw.is_a?(ActionController::Parameters))

        hash = if raw.respond_to?(:to_unsafe_h)
                 raw.to_unsafe_h
               else
                 raw.to_h
               end

        hash.is_a?(Hash) ? hash.stringify_keys : {}
      end

      def filtered_custom_field_params(custom_field)
        hash = raw_custom_field_params
        return {} if hash.empty?

        allowed = attribute_policy_for(custom_field).assignable_attributes
        return {} if allowed.empty?

        allowed_set = allowed.map(&:to_sym).to_set

        hash.each_with_object({}) do |(key, value), filtered|
          symbol = key.to_sym rescue nil
          next unless allowed_set.include?(symbol)

          filtered[key.to_s] = value
        end
      end

      def attribute_policy_for(custom_field)
        RedmineExtendedApi::CustomFields::AttributePolicy.new(custom_field)
      end

      def extract_enumerations_param(custom_field)
        raw_cf = params[:custom_field]
        return [] unless raw_cf.is_a?(ActionController::Parameters) || raw_cf.is_a?(Hash)

        hash = raw_cf.respond_to?(:to_unsafe_h) ? raw_cf.to_unsafe_h : raw_cf.to_h
        return [] unless hash.is_a?(Hash)

        field_format = hash['field_format'] || hash[:field_format] || custom_field.field_format
        return [] unless RedmineExtendedApi::CustomFields::AttributePolicy.enumeration_format?(field_format)

        enum_input = hash['enumerations'] || hash[:enumerations]
        return [] if enum_input.blank?

        list = enum_input.is_a?(Array) ? enum_input : [enum_input]

        list.each_with_index.map do |entry, idx|
          entry = entry.to_unsafe_h if entry.respond_to?(:to_unsafe_h)
          entry = entry.to_h        if entry.respond_to?(:to_h)
          next if entry.blank?

          {
            'id'       => entry['id'] || entry[:id],
            'name'     => entry['name'] || entry[:name],
            'position' => (entry['position'] || entry[:position] || idx + 1).to_i,
            'active'   => entry.key?('active') ? entry['active'] :
                            (entry.key?(:active) ? entry[:active] : true)
          }
        end.compact
      end

      def apply_enumerations(custom_field, enumeration_attrs)
        return if enumeration_attrs.blank?
        return unless custom_field.respond_to?(:enumerations)

        existing = custom_field.enumerations.to_a
        existing_by_id = existing.index_by(&:id)

        seen_ids = []

        enumeration_attrs.each do |attrs|
          name = attrs['name'].to_s.strip
          next if name.blank?

          if attrs['id'].present?
            # Bestaande enumeration bijwerken
            enum = existing_by_id[attrs['id'].to_i]
            next unless enum

            seen_ids << enum.id
            enum.name     = name
            enum.position = attrs['position'] if attrs['position']
            enum.active   = attrs['active'] unless attrs['active'].nil?
            enum.save if enum.changed?
          else
            # Nieuwe enumeration aanmaken
            enum = custom_field.enumerations.build(
              name:     name,
              position: attrs['position'],
              active:   attrs['active']
            )
            enum.save
            seen_ids << enum.id if enum.id
          end
        end

        # Optioneel: enumerations die niet meer in de lijst zitten verwijderen of inactief maken.
        # Als je ze wil verwijderen:
        #
        # (existing_by_id.keys - seen_ids).each do |id|
        #   existing_by_id[id].destroy
        # end
      end
    end
  end
end

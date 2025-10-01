# frozen_string_literal: true

require 'set'

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module CustomFieldsControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :show, :create, :update, :destroy
        base.helper_method :extended_api_metadata if base.respond_to?(:helper_method)
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

        assign_filtered_attributes(@custom_field)
        if @custom_field.save
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

        assign_filtered_attributes(@custom_field)
        if @custom_field.save
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

      def assign_filtered_attributes(custom_field)
        attributes = filtered_custom_field_params(custom_field)
        return if attributes.empty?

        custom_field.safe_attributes = attributes
      end

      def filtered_custom_field_params(custom_field)
        raw = params[:custom_field]
        return {} unless raw.respond_to?(:to_h)

        hash = if raw.respond_to?(:to_unsafe_h)
                 raw.to_unsafe_h
               else
                 raw.to_h
               end

        return {} unless hash.is_a?(Hash)

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
    end
  end
end

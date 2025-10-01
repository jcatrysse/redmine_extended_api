# frozen_string_literal: true

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

        @custom_field.safe_attributes = params[:custom_field]
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

      private

      def render_custom_field(status: :ok)
        render_extended_api(
          'custom_fields/show',
          status: status,
          location: custom_fields_url(format: api_request_format_symbol(:json))
        )
      end
    end
  end
end

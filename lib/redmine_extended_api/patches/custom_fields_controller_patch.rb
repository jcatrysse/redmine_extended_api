# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module CustomFieldsControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :create, :update, :destroy
      end

      def create
        return super unless api_request?

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
        return super unless api_request?

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
        return super unless api_request?

        if @custom_field.destroy
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
          location: custom_fields_url(format: request.format.symbol)
        )
      end
    end
  end
end

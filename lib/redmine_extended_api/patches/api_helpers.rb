# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    module ApiHelpers
      private

      def render_extended_api(template, status: :ok, location: nil)
        respond_to do |format|
          format.api do
            options = {template: "redmine_extended_api/#{template}", status: status}
            options[:location] = location if location
            render options
          end
        end
      end

      def render_api_validation_errors(record)
        respond_to do |format|
          format.api {render_validation_errors(record)}
        end
      end

      def render_api_error_message(message, status: :unprocessable_entity)
        respond_to do |format|
          format.api {render_error(message: message, status: status)}
        end
      end
    end
  end
end

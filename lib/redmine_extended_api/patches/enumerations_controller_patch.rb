# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module EnumerationsControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :create, :update, :destroy
      end

      def create
        return super unless api_request?

        if request.post? && @enumeration.save
          render_extended_api(
            'enumerations/show',
            status: :created,
            location: enumerations_url(format: request.format.symbol)
          )
        else
          render_api_validation_errors(@enumeration)
        end
      end

      def update
        return super unless api_request?

        if @enumeration.update(enumeration_params)
          render_extended_api('enumerations/show')
        else
          render_api_validation_errors(@enumeration)
        end
      end

      def destroy
        return super unless api_request?

        if !@enumeration.in_use?
          @enumeration.destroy
          head :no_content
        elsif params[:reassign_to_id].present? && (reassign_to = @enumeration.class.find_by_id(params[:reassign_to_id].to_i))
          @enumeration.destroy(reassign_to)
          head :no_content
        else
          message = I18n.t(
            :text_enumeration_destroy_question,
            name: @enumeration.name,
            count: @enumeration.objects_count
          )
          @enumeration.errors.add(:base, message)
          render_api_validation_errors(@enumeration)
        end
      end
    end
  end
end

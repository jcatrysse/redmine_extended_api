# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module RolesControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :show, :create, :update, :destroy
      end

      def create
        return super unless api_request?

        @role = Role.new
        @role.safe_attributes = params[:role]

        if request.post? && @role.save
          copy_workflow_from_role(@role, params[:copy_workflow_from])
          render_extended_api(
            'roles/show',
            status: :created,
            location: role_url(@role, format: request.format.symbol)
          )
        else
          render_api_validation_errors(@role)
        end
      end

      def update
        return super unless api_request?

        @role.safe_attributes = params[:role]

        if @role.save
          render_extended_api('roles/show')
        else
          render_api_validation_errors(@role)
        end
      end

      def destroy
        return super unless api_request?

        if destroy_role(@role)
          head :no_content
        else
          render_api_error_message(I18n.t(:error_can_not_remove_role))
        end
      end

      private

      def copy_workflow_from_role(role, copy_from_id)
        return if copy_from_id.blank?

        copy_from = Role.find_by_id(copy_from_id)
        role.copy_workflow_rules(copy_from) if copy_from
      end

      def destroy_role(role)
        role.destroy
        true
      rescue StandardError
        false
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module RolesControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :show, :create, :update, :destroy
        base.helper_method :extended_api_metadata if base.respond_to?(:helper_method)
      end

      def create
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

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
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        @role.safe_attributes = params[:role]

        if @role.save
          render_extended_api('roles/show')
        else
          render_api_validation_errors(@role)
        end
      end

      def destroy
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        if destroy_role(@role)
          mark_extended_api_response(fallback: false)
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

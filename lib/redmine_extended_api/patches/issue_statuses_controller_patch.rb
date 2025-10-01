# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module IssueStatusesControllerPatch
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

        @issue_status = IssueStatus.find(params[:id])
        render_extended_api('issue_statuses/show')
      rescue ActiveRecord::RecordNotFound
        render_api_not_found
      end

      def create
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        @issue_status = IssueStatus.new
        @issue_status.safe_attributes = params[:issue_status]

        if @issue_status.save
          render_extended_api(
            'issue_statuses/show',
            status: :created,
            location: issue_statuses_url(format: api_request_format_symbol(:json))
          )
        else
          render_api_validation_errors(@issue_status)
        end
      end

      def update
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        @issue_status = IssueStatus.find(params[:id])
        @issue_status.safe_attributes = params[:issue_status]

        if @issue_status.save
          render_extended_api('issue_statuses/show')
        else
          render_api_validation_errors(@issue_status)
        end
      end

      def destroy
        if !extended_api_request?
          return super if defined?(super)

          return render_404
        end

        issue_status = IssueStatus.find(params[:id])

        if issue_status.destroy
          mark_extended_api_response(fallback: false)
          head :no_content
        else
          render_api_validation_errors(issue_status)
        end
      end
    end
  end
end

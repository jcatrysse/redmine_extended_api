# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module IssueStatusesControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :create, :update, :destroy
      end

      def create
        return super unless api_request?

        @issue_status = IssueStatus.new
        @issue_status.safe_attributes = params[:issue_status]

        if @issue_status.save
          render_extended_api(
            'issue_statuses/show',
            status: :created,
            location: issue_statuses_url(format: request.format.symbol)
          )
        else
          render_api_validation_errors(@issue_status)
        end
      end

      def update
        return super unless api_request?

        @issue_status = IssueStatus.find(params[:id])
        @issue_status.safe_attributes = params[:issue_status]

        if @issue_status.save
          render_extended_api('issue_statuses/show')
        else
          render_api_validation_errors(@issue_status)
        end
      end

      def destroy
        return super unless api_request?

        issue_status = IssueStatus.find(params[:id])

        if issue_status.destroy
          head :no_content
        else
          render_api_validation_errors(issue_status)
        end
      end
    end
  end
end

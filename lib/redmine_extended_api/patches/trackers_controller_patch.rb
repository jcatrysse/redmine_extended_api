# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    module TrackersControllerPatch
      include ApiHelpers

      def self.prepended(base)
        base.accept_api_auth :index, :create, :update, :destroy
      end

      def create
        return super unless api_request?

        @tracker = Tracker.new
        @tracker.safe_attributes = params[:tracker]

        if @tracker.save
          copy_workflow_from_tracker(@tracker, params[:copy_workflow_from])
          render_extended_api(
            'trackers/show',
            status: :created,
            location: trackers_url(format: request.format.symbol)
          )
        else
          render_api_validation_errors(@tracker)
        end
      end

      def update
        return super unless api_request?

        @tracker = Tracker.find(params[:id])
        @tracker.safe_attributes = params[:tracker]

        if @tracker.save
          render_extended_api('trackers/show')
        else
          render_api_validation_errors(@tracker)
        end
      end

      def destroy
        return super unless api_request?

        tracker = Tracker.find(params[:id])
        if tracker.issues.empty?
          tracker.destroy
          head :no_content
        else
          projects = Project.joins(:issues).where(issues: {tracker_id: tracker.id}).sorted.distinct
          project_names = projects.map(&:to_s).join(', ')
          message = I18n.t(
            :error_can_not_delete_tracker_html,
            projects: project_names,
            default: I18n.t(:notice_failed_to_update, default: 'Unable to delete tracker')
          )
          render_api_error_message(ActionController::Base.helpers.strip_tags(message))
        end
      end

      private

      def copy_workflow_from_tracker(tracker, copy_from_id)
        return if copy_from_id.blank?

        copy_from = Tracker.find_by_id(copy_from_id)
        tracker.copy_workflow_rules(copy_from) if copy_from
      end
    end
  end
end

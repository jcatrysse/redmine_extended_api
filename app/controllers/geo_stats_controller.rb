# frozen_string_literal: true

class GeoStatsController < ApplicationController
  before_action :require_login
  accept_api_auth :monthly_flow

  def monthly_flow
    project = Project.find(params[:project_id])

    unless User.current.allowed_to?(:view_issues, project)
      render json: { error: 'Forbidden' }, status: :forbidden and return
    end

    raw    = params[:months].to_i
    months = raw.positive? ? [raw, 24].min : 6

    result = GeoStats::QueryAggregator.aggregate(
      Issue.where(project_id: project.id),
      period:  'month',
      periods: months
    )

    render json: {
      labels:       result['labels'],
      created:      result['created'],
      closed:       result['closed'],
      open_now:     result['open_now'],
      total:        result['total'],
      project:      project.identifier,
      months:       months,
      generated_at: Time.now.iso8601
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Project not found' }, status: :not_found
  end
end

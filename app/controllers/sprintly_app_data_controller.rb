# frozen_string_literal: true

# SPR-553: the signed-in user's own "App data" (the SPA's dashboards and saved filters), and
# nobody else's — there is no user parameter.
#
#   GET /sprintly/me/app_data.json
#     → { "app_data": { "value": "{…}" | null, "digest": "<sha256>" } }
#   PUT /sprintly/me/app_data.json  { "app_data": { "value": "{…}", "digest": "<as read>" } }
#     → the same shape, after the write. `value` is the whole document, a JSON object as a
#     string. With `digest`, a value changed since it was read is not overwritten:
#     409 with the current value and digest, so the client merges and tries again.
#     Without it the write is unconditional. 422 on a value that is not a JSON object or is
#     too large.
#
# Works whether or not the field is `visible` (see Sprintly::AppData). Also reachable through
# the proxy as /extended_api/sprintly/... .
class SprintlyAppDataController < ApplicationController
  AppData = RedmineExtendedApi::Sprintly::AppData

  accept_api_auth :show, :update

  before_action :require_login

  def show
    render_value(AppData.read(User.current).first)
  end

  def update
    body = params[:app_data]
    return render_error_json('app_data missing', :unprocessable_entity) unless body.respond_to?(:key?) && body.key?(:value)

    expected = body[:digest].presence&.to_s
    render_value(AppData.write!(User.current, body[:value], expected))
  rescue AppData::InvalidValueError => e
    render_error_json(e.message, :unprocessable_entity)
  rescue AppData::ConflictError => e
    current = AppData.read(User.current).first
    render json: { errors: [e.message], app_data: payload(current) }, status: :conflict
  end

  private

  def render_value(value)
    render json: { app_data: payload(value) }
  end

  def payload(value)
    { value: value.presence, digest: AppData.digest(value) }
  end

  def render_error_json(message, status)
    render json: { errors: [message] }, status: status
  end
end

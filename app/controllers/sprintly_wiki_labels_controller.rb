# frozen_string_literal: true

# SPR-530: labels of wiki pages, for the SPA's page header and the label filter of its tree.
#
#   GET /sprintly/projects/:project_id/wiki/labels.json
#     → { "labels": [{ "title": "Page", "labels": ["how-to", "release"] }, …] }
#     the pages of the project's wiki that have labels; needs view_wiki_pages.
#   PUT /sprintly/projects/:project_id/wiki/labels.json  { "title": "Page", "labels": [...] }
#     → { "title": "Page", "labels": [...] }  sets the page's labels (all of them).
#
# Labelling a page is editing it: core `edit_wiki_pages` (and, with the Sprintly role model,
# `wiki.edit` — creating pages is not enough), and a protected page only for who may protect.
# Also reachable through the proxy as /extended_api/sprintly/... .
class SprintlyWikiLabelsController < ApplicationController
  include RedmineExtendedApi::Sprintly::ControllerPatches::Guard

  Labels = RedmineExtendedApi::Sprintly::WikiLabels

  accept_api_auth :index, :update

  before_action :find_project_wiki

  def index
    render json: { labels: Labels.by_page_title(@wiki).map { |title, names| { title: title, labels: names } } }
  end

  def update
    page = @wiki.find_page(params[:title].to_s)
    return render_404 unless page
    return deny_access unless may_label?(page)
    return render_error_json('labels missing') unless params.key?(:labels)

    names = Array(params[:labels]).map { |name| Labels.normalize(name) }.reject(&:empty?).uniq
    too_long = names.select { |name| name.length > Labels::MAX_LENGTH }
    return render_error_json("labels longer than #{Labels::MAX_LENGTH} characters: #{too_long.join(', ')}") if too_long.any?
    return render_error_json("at most #{Labels::MAX_PER_PAGE} labels per page") if names.size > Labels::MAX_PER_PAGE

    render json: { title: page.title, labels: Labels.set!(page, names) }
  end

  private

  def may_label?(page)
    return false unless User.current.allowed_to?(:edit_wiki_pages, @project) && page.editable_by?(User.current)

    !sprintly_enforced? || sprintly_allowed?('wiki.edit')
  end

  def find_project_wiki
    @project = Project.find(params[:project_id])
    @wiki = @project.wiki
    return render_404 unless @wiki
    return deny_access unless User.current.allowed_to?(:view_wiki_pages, @project)

    true
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def render_error_json(message)
    render json: { errors: [message] }, status: :unprocessable_entity
  end
end

# frozen_string_literal: true

# SPR-521: a wiki page's history, the comparison of two versions and "who wrote which block",
# as JSON. Core Redmine has them only as HTML pages (wiki#history, #diff, #annotate) and the
# SPA otherwise reads every version with its full text to build a history list.
#
# Reached as /sprintly/projects/:project_id/wiki/:id/... and, through the proxy, as
# /extended_api/sprintly/projects/:project_id/wiki/:id/... . Same right as core's pages:
# `view_wiki_edits` (in the Sprintly role model it comes with `wiki.view`).
class SprintlyWikiController < ApplicationController
  WikiBlocks = RedmineExtendedApi::Sprintly::WikiBlocks

  HISTORY_LIMIT = 25
  HISTORY_MAX_LIMIT = 100

  accept_api_auth :history, :diff, :annotate

  before_action :find_wiki_page
  before_action :authorize_wiki_edits

  # The versions of the page, newest first, without their text.
  def history
    limit = params[:limit].to_i
    limit = HISTORY_LIMIT if limit <= 0
    limit = [limit, HISTORY_MAX_LIMIT].min
    offset = [params[:offset].to_i, 0].max
    scope = @page.content.versions
    versions = scope.select(:id, :author_id, :comments, :updated_on, :version).preload(:author)
                    .reorder(version: :desc).limit(limit).offset(offset).to_a
    render json: {
      wiki_page: { title: @page.title, version: @page.content.version },
      versions: versions.map { |version| version_payload(version) },
      total_count: scope.count, offset: offset, limit: limit
    }
  end

  # The blocks of two versions compared: `version` (the newest by default) against
  # `version_from` (the one before it by default), the older one always on the left.
  def diff
    to_number = params[:version].present? ? params[:version].to_i : @page.content.version
    content_to = @page.content.versions.find_by(version: to_number)
    content_from =
      if params[:version_from].present?
        @page.content.versions.find_by(version: params[:version_from].to_i)
      else
        content_to&.previous
      end
    return render_404 unless content_to && content_from

    content_to, content_from = content_from, content_to if content_from.version > content_to.version
    blocks = WikiBlocks.diff(WikiBlocks.blocks_of(content_from.text), WikiBlocks.blocks_of(content_to.text))
    render json: {
      wiki_diff: {
        title: @page.title,
        version_from: version_payload(content_from),
        version_to: version_payload(content_to),
        blocks: blocks.map { |op, text| { op: op, text: text } }
      }
    }
  end

  # Every block of a version (the newest by default) with the version and author that
  # brought it in.
  def annotate
    number = params[:version].present? ? params[:version].to_i : @page.content.version
    content = @page.content.versions.find_by(version: number)
    return render_404 unless content

    lines = WikiBlocks.annotate(content)
    render json: {
      wiki_annotate: {
        title: @page.title,
        version: content.version,
        lines: lines.map { |version, author, text| { version: version, author: author_payload(author), text: text } }
      }
    }
  end

  private

  def find_wiki_page
    @project = Project.find(params[:project_id])
    @wiki = @project.wiki
    @page = @wiki&.find_page(params[:id])
    render_404 unless @page&.content
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_wiki_edits
    return true if User.current.allowed_to?(:view_wiki_edits, @project)

    deny_access
  end

  def version_payload(version)
    {
      version: version.version,
      author: author_payload(version.author),
      comments: version.comments.to_s,
      updated_on: version.updated_on&.utc&.iso8601
    }
  end

  def author_payload(author)
    author ? { id: author.id, name: author.name } : nil
  end
end

# frozen_string_literal: true

# SPR-529: comments under a wiki page (SprintlyWikiComment).
#
# Reached as /sprintly/projects/:project_id/wiki/comments and, through the proxy, as
# /extended_api/sprintly/projects/:project_id/wiki/comments . The page is named by `title`
# (see WikiSocial::PageFinder); a comment by its id.
#
# Rights, in the page's project: reading and writing comments come with reading the page
# (`view_wiki_pages`, i.e. `wiki.view`), writing needs the project open; editing a comment
# is for its author, deleting one for its author or whoever may delete the page.
class SprintlyWikiCommentsController < ApplicationController
  include RedmineExtendedApi::Sprintly::WikiSocial::PageFinder

  accept_api_auth :index, :create, :update, :destroy

  before_action :require_login
  before_action :find_wiki_page, only: %i[index create]
  before_action :find_comment, only: %i[update destroy]

  def index
    list = @page.sprintly_wiki_comments.preload(:author).order(:created_on, :id).to_a
    render json: { comments: list.map { |c| comment_payload(c) }, total_count: list.size,
                   can_comment: SprintlyWikiComment.commentable?(@page) }
  end

  def create
    return render_403 unless SprintlyWikiComment.commentable?(@page)

    comment = @page.sprintly_wiki_comments.build(author: User.current)
    comment.safe_attributes = comment_params
    if comment.save
      render json: { comment: comment_payload(comment) }, status: :created
    else
      render_validation_errors(comment)
    end
  end

  def update
    return render_403 unless @comment.editable?

    @comment.safe_attributes = comment_params
    if @comment.save
      render json: { comment: comment_payload(@comment) }
    else
      render_validation_errors(@comment)
    end
  end

  def destroy
    return render_403 unless @comment.deletable?

    @comment.destroy
    head :no_content
  end

  private

  def find_comment
    find_project_wiki
    return if performed?

    @comment = SprintlyWikiComment.joins(:page).where(wiki_pages: { wiki_id: @wiki.id }).find_by(id: params[:id])
    return render_404 unless @comment

    @page = @comment.page
    render_403 unless @page.visible?
  end

  def comment_params
    raw = params[:comment]
    raw.respond_to?(:permit) ? raw.permit(:content) : {}
  end

  def comment_payload(comment)
    author = comment.author || User.anonymous
    {
      id: comment.id,
      content: comment.content,
      author: { id: author.id, name: author.name },
      created_on: comment.created_on&.utc&.iso8601,
      updated_on: comment.updated_on&.utc&.iso8601,
      editable: comment.editable?,
      deletable: comment.deletable?
    }
  end
end

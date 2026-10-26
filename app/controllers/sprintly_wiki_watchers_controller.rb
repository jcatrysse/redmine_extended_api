# frozen_string_literal: true

# SPR-523: who watches a wiki page, and watching it.
#
# Core REST cannot list a page's watchers, and its show answers no page id to watch it by.
# Pages are addressed by title (see WikiSocial::PageFinder).
#
# Reached as /sprintly/projects/:project_id/wiki/watchers and, through the proxy, as
# /extended_api/sprintly/projects/:project_id/wiki/watchers .
#
# Rights, in the page's project: the list and watching or unwatching yourself come with
# reading the page (`view_wiki_pages`, i.e. `wiki.view`) — like watching an issue, which
# needs no more than seeing it; changes need the project open. Adding or removing somebody
# else is core's `add_wiki_page_watchers` / `delete_wiki_page_watchers`.
class SprintlyWikiWatchersController < ApplicationController
  include RedmineExtendedApi::Sprintly::WikiSocial::PageFinder

  accept_api_auth :index, :create, :destroy

  before_action :require_login
  before_action :find_wiki_page

  def index
    render json: watchers_payload
  end

  def create
    user = target_user
    return unless user
    return render_403 unless may_change?(user, :add_wiki_page_watchers)
    unless @page.visible?(user)
      return render json: { errors: [l(:error_sprintly_wiki_watcher_cannot_view)] }, status: :unprocessable_entity
    end

    @page.add_watcher(user) unless @page.watcher_user_ids.include?(user.id)
    render json: watchers_payload
  end

  def destroy
    user = target_user
    return unless user
    return render_403 unless may_change?(user, :delete_wiki_page_watchers)

    @page.remove_watcher(user)
    render json: watchers_payload
  end

  private

  # Yourself, unless `user_id` names somebody else.
  def target_user
    return User.current if params[:user_id].blank?

    user = User.active.find_by(id: params[:user_id])
    render_404 unless user
    user
  end

  def may_change?(user, others_permission)
    return false unless @project.active?
    return true if user == User.current

    User.current.allowed_to?(others_permission, @project)
  end

  def watchers_payload
    principals = @page.watcher_users.to_a.sort_by(&:name)
    {
      watchers: principals.map { |p| { id: p.id, name: p.name, type: p.is_a?(Group) ? 'group' : 'user' } },
      watching: @page.watched_by?(User.current),
      can_watch: @project.active?,
      can_manage: @project.active? && User.current.allowed_to?(:add_wiki_page_watchers, @project)
    }
  end
end

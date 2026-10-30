# frozen_string_literal: true

# SPR-524: "Linked from" of a wiki page in one request.
#
# The SPA used to read every page of the project (one GET each) to find which of them hold a
# [[link]] to the page shown. Here it is one query over the wiki's current texts: only texts
# holding a `[[` are read, then parsed the way the SPA parses them (`wiki-links.ts`).
#
# GET /sprintly/projects/:project_id/wiki/backlinks.json?title=Page — also reachable through
# the proxy as /extended_api/sprintly/... . Who may read the project's wiki may ask.
class SprintlyWikiLinksController < ApplicationController
  # [[Target]] or [[Target|alias]]. Target excludes ']' and '|'; alias excludes ']'.
  WIKI_LINK = /\[\[([^\]|]+?)(?:\|[^\]]+?)?\]\]/

  accept_api_auth :backlinks

  before_action :find_project_wiki

  def backlinks
    page = @wiki.find_page(params[:title].to_s)
    return render_404 unless page

    # A renamed page is still reached by links to its old titles (Redmine keeps redirects).
    targets = [page.title] + WikiRedirect.where(wiki_id: @wiki.id, redirects_to: page.title).pluck(:title)
    keys = targets.map { |title| self.class.title_key(title) }.to_set

    rows = WikiContent.joins(:page)
                      .where(wiki_pages: { wiki_id: @wiki.id })
                      .where.not(page_id: page.id)
                      .where('wiki_contents.text LIKE ?', '%[[%')
                      .pluck('wiki_pages.title', 'wiki_pages.parent_id', 'wiki_contents.updated_on', 'wiki_contents.text')

    parents = WikiPage.where(id: rows.map { |r| r[1] }.compact.uniq).pluck(:id, :title).to_h
    linking = rows.select { |(_title, _parent, _updated, text)| self.class.link_keys(text).intersect?(keys) }
    render json: {
      title: page.title,
      backlinks: linking.sort_by { |(title, *)| title.downcase }.map do |(title, parent_id, updated_on, _text)|
        { title: title, parent_title: parents[parent_id], updated_on: updated_on }
      end
    }
  end

  # "Getting Started" == "getting_started" — the SPA's `normalizeTitleKey`, plus the HTML
  # escaping of rich text (`Q&amp;A`) undone.
  def self.title_key(title)
    CGI.unescapeHTML(title.to_s).strip.gsub(/[_\s]+/, ' ').downcase
  end

  # Keys of every page a text links to; `[[Page#section]]` links to Page.
  def self.link_keys(text)
    text.to_s.scan(WIKI_LINK).map { |(target)| title_key(target.split('#', 2).first) }.reject(&:empty?).to_set
  end

  private

  def find_project_wiki
    @project = Project.find(params[:project_id])
    @wiki = @project.wiki
    return render_404 unless @wiki
    return deny_access unless User.current.allowed_to?(:view_wiki_pages, @project)

    true
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end

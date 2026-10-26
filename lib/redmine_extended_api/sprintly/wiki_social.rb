# frozen_string_literal: true

module RedmineExtendedApi
  module Sprintly
    # SPR-523 / SPR-529: what wiki watchers and page comments need from core models.
    module WikiSocial
      # For controllers: the wiki page of the request. The title is a parameter (`?title=`)
      # rather than a path segment, so a title with a dot never meets the `.json` suffix;
      # a renamed page is found through its redirect, like core's show does.
      module PageFinder
        private

        def find_project_wiki
          @project = Project.find(params[:project_id])
          @wiki = @project.wiki
          render_404 unless @wiki
        rescue ActiveRecord::RecordNotFound
          render_404
        end

        def find_wiki_page
          find_project_wiki
          return if performed?

          title = params[:title].to_s
          @page = @wiki.find_page(title) if title.present?
          return render_404 unless @page

          render_403 unless @page.visible?
        end
      end
    end
  end
end

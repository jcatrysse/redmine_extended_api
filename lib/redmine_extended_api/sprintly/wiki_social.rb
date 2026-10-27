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

      # The SPA's editor writes a mention as `<span data-type="mention" data-id="5">@Jane Doe</span>`:
      # the label is the display name, so Redmine's own `@login` scan finds nobody. Mentionable
      # models get the logins of those ids too, which makes core's mention mail (wiki content)
      # and ours (comments) reach the people mentioned in the SPA. Only newly mentioned people
      # count — Mentionable compares the old and new text.
      module Mentions
        module_function

        def user_ids_in(html)
          return [] if html.blank? || !html.include?('mention')

          Nokogiri::HTML::DocumentFragment.parse(html)
                                          .css('[data-type="mention"][data-id]')
                                          .map { |node| node['data-id'].to_i }
                                          .select(&:positive?)
                                          .uniq
        end

        def logins_in(html)
          ids = user_ids_in(html)
          ids.empty? ? [] : User.where(id: ids).pluck(:login)
        end
      end

      # Prepended to WikiContent; included in SprintlyWikiComment after `acts_as_mentionable`.
      module MentionScan
        private

        def scan_for_mentioned_users(content)
          (super + Mentions.logins_in(content)).uniq
        end
      end

      # A page's comments go with it.
      module WikiPagePatch
        def self.included(base)
          base.has_many :sprintly_wiki_comments, class_name: 'SprintlyWikiComment', foreign_key: :commented_id,
                                                 dependent: :delete_all, inverse_of: :page
        end
      end
    end
  end
end

# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    # SPR-530: a wiki page's labels go with it when it is deleted.
    module WikiPageLabelsPatch
      def self.included(base)
        base.has_many :sprintly_labels, class_name: 'SprintlyWikiPageLabel', foreign_key: :wiki_page_id,
                                        dependent: :delete_all, inverse_of: :wiki_page
      end
    end
  end
end

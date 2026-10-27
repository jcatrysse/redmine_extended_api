# frozen_string_literal: true

module RedmineExtendedApi
  module Patches
    # SPR-530: a wiki page's labels go with it when it is deleted.
    module WikiPageLabelsPatch
      def self.included(base)
        base.after_destroy_commit { RedmineExtendedApi::Sprintly::WikiLabels.forget!(id) }
      end
    end
  end
end

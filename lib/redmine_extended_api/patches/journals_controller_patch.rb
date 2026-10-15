# frozen_string_literal: true

require_relative 'api_helpers'

module RedmineExtendedApi
  module Patches
    # skip_journal on PUT /extended_api/journals/:id (see ApiHelpers). An around_action, not a
    # prepended update: no core method is overridden (see IssuePatch). Runs after core's
    # find_journal and authorize.
    module JournalsControllerPatch
      include ApiHelpers

      def self.included(base)
        base.around_action :with_extended_api_journal_context, only: :update
      end

      private

      def with_extended_api_journal_context(&block)
        return yield unless extended_api_request?
        return if render_refused_extended_api_skip_journal

        with_extended_api_skip_journal(&block)
      end
    end
  end
end

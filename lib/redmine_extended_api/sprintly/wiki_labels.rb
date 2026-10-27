# frozen_string_literal: true

require 'json'

module RedmineExtendedApi
  module Sprintly
    # SPR-530: labels of wiki pages, kept like the role model (Store): one JSON document in this
    # plugin's settings rather than a table of its own. Tenants start from a prepared database
    # dump and plugin migrations are not run on them, so the plugin only uses tables core has.
    #
    #   { "<wiki page id>": ["how-to", "release"], … }
    #
    # Keyed by page id, so a rename keeps a page's labels; a deleted page's entry goes with it
    # (WikiPageLabelsPatch). Labels are lower case words: `Release Notes` is stored as
    # `release-notes`, so the same label is never there twice in different spellings.
    module WikiLabels
      KEY = 'sprintly_wiki_labels'
      MAX_LENGTH = 40
      MAX_PER_PAGE = 20

      module_function

      # Lower case, inner spaces as `-`, only letters, digits, `-`, `_` and `.`; '' when nothing is left.
      def normalize(name)
        name.to_s.strip.downcase.gsub(/\s+/, '-').gsub(/[^\p{L}\p{N}_.-]/, '').gsub(/-{2,}/, '-').delete_prefix('-').delete_suffix('-')
      end

      # page id (string) => label names. A fresh copy every call.
      def read
        raw = Store.settings_hash[KEY]
        return {} if raw.blank?

        data = raw.is_a?(String) ? JSON.parse(raw) : raw.to_h
        data.each_with_object({}) do |(page_id, names), out|
          list = Array(names).map(&:to_s).reject(&:empty?)
          out[page_id.to_s] = list if list.any?
        end
      rescue JSON::ParserError
        {}
      end

      def of(page)
        read[page.id.to_s] || []
      end

      # page title => sorted label names, for the pages of `wiki` that have labels.
      def by_page_title(wiki)
        data = read
        return {} if data.empty?

        WikiPage.where(wiki_id: wiki.id, id: data.keys.map(&:to_i)).order(:title).pluck(:id, :title)
                .to_h { |id, title| [title, data[id.to_s].sort] }
      end

      # Sets all labels of `page` (already normalized) and returns them sorted.
      def set!(page, names)
        update! do |data|
          if names.empty?
            data.delete(page.id.to_s)
          else
            data[page.id.to_s] = names.uniq.sort
          end
        end
        of(page)
      end

      def forget!(page_id)
        update! { |data| data.delete(page_id.to_s) } if read.key?(page_id.to_s)
      end

      # Read-modify-write under the same row lock as Store.update!: the role model and the labels
      # share one settings row, so neither may write it from a stale copy.
      def update!
        Setting.transaction do
          Setting.where(name: Store::SETTING_NAME).lock.first
          Setting.clear_cache
          data = read
          yield data
          settings = Store.settings_hash.dup
          if data.empty?
            settings.delete(KEY)
          else
            settings[KEY] = JSON.generate(data)
          end
          Setting.send(:"#{Store::SETTING_NAME}=", settings)
        end
      end
    end
  end
end

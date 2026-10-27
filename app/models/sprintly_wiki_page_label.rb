# frozen_string_literal: true

# SPR-530: one label of one wiki page. Labels are lower case words: `Release Notes` is stored
# as `release-notes`, so the same label is never there twice in different spellings.
class SprintlyWikiPageLabel < ApplicationRecord
  MAX_LENGTH = 40
  MAX_PER_PAGE = 20

  belongs_to :wiki_page

  validates :name, presence: true, length: { maximum: MAX_LENGTH }, uniqueness: { scope: :wiki_page_id }

  before_create { self.created_on ||= Time.now }

  # Lower case, inner spaces as `-`, only letters, digits, `-`, `_` and `.`; '' when nothing is left.
  def self.normalize(name)
    name.to_s.strip.downcase.gsub(/\s+/, '-').gsub(/[^\p{L}\p{N}_.-]/, '').gsub(/-{2,}/, '-').delete_prefix('-').delete_suffix('-')
  end

  # page title => sorted label names, for the pages of `wiki` that have labels.
  def self.by_page_title(wiki)
    joins(:wiki_page).where(wiki_pages: { wiki_id: wiki.id })
                     .order('wiki_pages.title', :name)
                     .pluck('wiki_pages.title', :name)
                     .each_with_object({}) { |(title, name), out| (out[title] ||= []) << name }
  end
end

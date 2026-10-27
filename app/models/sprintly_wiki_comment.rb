# frozen_string_literal: true

# SPR-529: a comment under a wiki page (Confluence's page comments). Redmine has none: this
# is a flat thread per page — no replies, no anchors in the text.
#
# The text is HTML from the SPA's editor, cleaned on save to the markup that editor writes
# (mentions, lists, checklists, code, links); the SPA renders it like an issue comment.
#
# Stored in core's polymorphic `comments` table (the one news comments use) as
# commented_type 'WikiPage': tenants start from a prepared database dump and plugin
# migrations are not run on them, so the plugin only uses tables core has. Not core's
# Comment class itself: its counter cache would look for `wiki_pages.comments_count` and
# it mails through events core has no wiki template for.
class SprintlyWikiComment < ApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'comments'
  default_scope { where(commented_type: 'WikiPage') }

  ALLOWED_TAGS = %w[
    p br strong b em i u s strike del code pre blockquote ul ol li a span div label input
    h1 h2 h3 h4 h5 h6 hr table thead tbody tr th td
  ].freeze
  ALLOWED_ATTRIBUTES = %w[
    href class type checked colspan rowspan
    data-type data-id data-label data-checked data-mention-suggestion-char
  ].freeze
  MAX_LENGTH = 100_000

  belongs_to :page, class_name: 'WikiPage', foreign_key: :commented_id, inverse_of: :sprintly_wiki_comments
  belongs_to :author, class_name: 'User'

  acts_as_mentionable attributes: ['content']
  include RedmineExtendedApi::Sprintly::WikiSocial::MentionScan

  safe_attributes 'content'

  before_validation :clean_content
  validates :content, presence: true, length: { maximum: MAX_LENGTH }

  after_create_commit :send_notification_create
  after_update_commit :send_notification_update

  def project
    page&.project
  end

  def visible?(user = User.current)
    page.present? && page.visible?(user)
  end

  # Comments are part of reading the page: whoever may read it may comment, while the
  # project is open.
  def self.commentable?(page, user = User.current)
    user.logged? && page.visible?(user) && page.project.active?
  end

  # Your own comment, while you could still write it.
  def editable?(user = User.current)
    author_id == user.id && self.class.commentable?(page, user)
  end

  # Yours, or anybody's for whoever may delete the page itself (and so its comments).
  def deletable?(user = User.current)
    editable?(user) || (page.project.active? && user.allowed_to?(:delete_wiki_pages, page.project))
  end

  private

  def clean_content
    return if content.nil?

    self.content = ActionController::Base.helpers.sanitize(
      content.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
    ).to_s.strip
    # A comment of empty paragraphs is no comment.
    self.content = '' if Nokogiri::HTML::DocumentFragment.parse(content).text.strip.empty? &&
                         RedmineExtendedApi::Sprintly::WikiSocial::Mentions.user_ids_in(content).empty?
  end

  # Mentioned people always hear of it; watchers of the page (or of the whole wiki) do when
  # the tenant mails wiki changes, like core does for an edit of the page.
  def send_notification_create
    users = notified_mentions
    if Setting.notified_events.include?('wiki_content_updated')
      users |= page.notified_watchers
      users |= page.wiki.notified_watchers
    end
    deliver_to(users)
  end

  # An edit tells only the people it mentions anew.
  def send_notification_update
    deliver_to(notified_mentions) if saved_change_to_content?
  end

  def deliver_to(users)
    mentioned = mentioned_users.to_a
    users.reject { |user| user.id == author_id }.each do |user|
      SprintlyWikiMailer.wiki_comment_added(user, self, mentioned.include?(user)).deliver_later
    end
  end
end

# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# SPR-529: comments under a wiki page, and mentions in them and in the page itself.
#
# Fixtures: project 1 (ecookbook, public) has jsmith (2, Manager: may delete pages) and
# dlopper (3, Developer: may delete pages too in the fixtures, so a role without it is made
# here); rhill (4) is no member and reads it as Non member. Project 2 (onlinestore) is private.
class SprintlyWikiCommentsTest < Redmine::ApiTest::Base
  Sprintly = RedmineExtendedApi::Sprintly
  PASSWORDS = { 'dlopper' => 'foo', 'rhill' => 'rhill-secret' }.freeze
  URL = '/sprintly/projects/ecookbook/wiki/comments'

  def setup
    super
    User.find(4).update!(password: 'rhill-secret', password_confirmation: 'rhill-secret')
    ActionMailer::Base.deliveries.clear
  end

  def auth(login)
    credentials(login, PASSWORDS[login])
  end

  def json_headers(login)
    auth(login).merge('CONTENT_TYPE' => 'application/json')
  end

  def body
    JSON.parse(response.body)
  end

  def mention(user)
    %(<span class="mention" data-type="mention" data-id="#{user.id}" data-label="#{user.name}">@#{user.name}</span>)
  end

  def create_comment(login, content, title: 'Another_page')
    post "#{URL}.json", params: { title: title, comment: { content: content } }.to_json, headers: json_headers(login)
    assert_response :created
    body['comment']
  end

  def recipients
    ActionMailer::Base.deliveries.flat_map(&:to).sort
  end

  def test_create_and_list
    created = create_comment('dlopper', '<p>First <strong>one</strong></p>')
    assert_equal '<p>First <strong>one</strong></p>', created['content']
    assert_equal({ 'id' => 3, 'name' => 'Dave Lopper' }, created['author'])
    assert created['editable']
    assert created['created_on'].end_with?('Z')
    create_comment('rhill', '<p>Second</p>')

    get "#{URL}.json", params: { title: 'Another page' }, headers: auth('dlopper')
    assert_response :success
    assert_equal 2, body['total_count']
    assert_equal ['<p>First <strong>one</strong></p>', '<p>Second</p>'], body['comments'].map { |c| c['content'] }
    assert_equal [true, false], body['comments'].map { |c| c['editable'] }, 'only your own is editable'
    assert body['can_comment']

    get "#{URL}.json", params: { title: 'CookBook_documentation' }, headers: auth('dlopper')
    assert_equal [], body['comments'], 'comments belong to their page'
  end

  def test_content_is_cleaned_and_required
    created = create_comment('dlopper', %(<p onclick="x()">Hi <script>alert(1)</script><a href="javascript:x()">a</a> ) +
                                        %(<a href="https://example.com">b</a> #{mention(User.find(2))}</p>))
    refute_includes created['content'], 'script'
    refute_includes created['content'], 'onclick'
    refute_includes created['content'], 'javascript:'
    assert_includes created['content'], 'href="https://example.com"'
    assert_includes created['content'], 'data-id="2"', 'mentions keep their user id'

    post "#{URL}.json", params: { title: 'Another_page', comment: { content: '<p> </p><p></p>' } }.to_json,
                        headers: json_headers('dlopper')
    assert_response :unprocessable_entity
    post "#{URL}.json", params: { title: 'Another_page' }.to_json, headers: json_headers('dlopper')
    assert_response :unprocessable_entity
  end

  def test_edit_your_own_only
    comment = create_comment('dlopper', '<p>Typo</p>')
    put "#{URL}/#{comment['id']}.json", params: { comment: { content: '<p>Fixed</p>' } }.to_json,
                                        headers: json_headers('dlopper')
    assert_response :success
    assert_equal '<p>Fixed</p>', body['comment']['content']
    assert_equal '<p>Fixed</p>', SprintlyWikiComment.find(comment['id']).content

    put "#{URL}/#{comment['id']}.json", params: { comment: { content: '<p>Mine now</p>' } }.to_json,
                                        headers: json_headers('jsmith')
    assert_response :forbidden
    put "#{URL}/#{comment['id']}.json", params: { comment: { content: '' } }.to_json, headers: json_headers('dlopper')
    assert_response :unprocessable_entity
  end

  def test_delete_your_own_or_as_who_may_delete_the_page
    mine = create_comment('rhill', '<p>Spam</p>')
    other = create_comment('dlopper', '<p>Keep</p>')
    delete "#{URL}/#{other['id']}.json", headers: auth('rhill')
    assert_response :forbidden, 'Non member may not delete pages'
    delete "#{URL}/#{mine['id']}.json", headers: auth('rhill')
    assert_response :no_content

    get "#{URL}.json", params: { title: 'Another_page' }, headers: auth('jsmith')
    assert_equal [true], body['comments'].map { |c| c['deletable'] }, 'the Manager may delete pages'
    delete "#{URL}/#{other['id']}.json", headers: auth('jsmith')
    assert_response :no_content
    assert_equal 0, SprintlyWikiComment.count
  end

  def test_a_page_you_cannot_read
    page = WikiPage.find(3) # project 2, private
    comment = SprintlyWikiComment.create!(page: page, author: User.find(2), content: '<p>Secret</p>')
    get '/sprintly/projects/onlinestore/wiki/comments.json', params: { title: page.title }, headers: auth('rhill')
    assert_response :forbidden
    post '/sprintly/projects/onlinestore/wiki/comments.json',
         params: { title: page.title, comment: { content: '<p>x</p>' } }.to_json, headers: json_headers('rhill')
    assert_response :forbidden
    delete "/sprintly/projects/onlinestore/wiki/comments/#{comment.id}.json", headers: auth('rhill')
    assert_response :forbidden
    delete "#{URL}/#{comment.id}.json", headers: auth('jsmith')
    assert_response :not_found, 'a comment is found in the wiki of the project in the address only'
    get "#{URL}.json", params: { title: 'Nope' }, headers: auth('jsmith')
    assert_response :not_found
  end

  def test_a_closed_project_is_read_only
    comment = create_comment('dlopper', '<p>Before</p>')
    Project.find(1).close
    get "#{URL}.json", params: { title: 'Another_page' }, headers: auth('dlopper')
    assert_response :success
    refute body['can_comment']
    refute body['comments'].first['editable']
    post "#{URL}.json", params: { title: 'Another_page', comment: { content: '<p>x</p>' } }.to_json,
                        headers: json_headers('dlopper')
    assert_response :forbidden
    delete "#{URL}/#{comment['id']}.json", headers: auth('jsmith')
    assert_response :forbidden
  end

  def test_mentioned_people_are_mailed
    with_settings notified_events: [] do
      create_comment('dlopper', "<p>#{mention(User.find(2))} have a look</p>")
    end
    assert_equal ['jsmith@somenet.foo'], recipients
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.subject, 'Another page'
    assert_includes mail.text_part.body.to_s, 'mentioned you'
    assert_includes mail.text_part.body.to_s, 'have a look'
  end

  def test_a_mention_of_someone_who_cannot_read_the_page_is_not_mailed
    page = WikiPage.find(3) # project 2, private: rhill is no member
    with_settings notified_events: [] do
      post '/sprintly/projects/onlinestore/wiki/comments.json',
           params: { title: page.title, comment: { content: "<p>#{mention(User.find(4))}</p>" } }.to_json,
           headers: json_headers('jsmith')
    end
    assert_response :created
    assert_empty recipients
  end

  def test_an_edit_mails_only_the_people_mentioned_anew
    comment = with_settings(notified_events: []) { create_comment('dlopper', "<p>#{mention(User.find(2))}</p>") }
    ActionMailer::Base.deliveries.clear
    with_settings notified_events: [] do
      put "#{URL}/#{comment['id']}.json",
          params: { comment: { content: "<p>#{mention(User.find(2))} and #{mention(User.find(1))}</p>" } }.to_json,
          headers: json_headers('dlopper')
    end
    assert_response :success
    assert_equal ['admin@somenet.foo'], recipients
  end

  def test_watchers_are_mailed_when_the_tenant_mails_wiki_changes
    WikiPage.find(2).add_watcher(User.find(2))
    with_settings notified_events: [] do
      create_comment('dlopper', '<p>Quiet</p>')
    end
    assert_empty recipients
    with_settings notified_events: %w[wiki_content_updated] do
      create_comment('dlopper', '<p>Loud</p>')
      create_comment('jsmith', '<p>Nobody hears of their own comment</p>')
    end
    assert_equal ['jsmith@somenet.foo'], recipients
  end

  def test_mentions_in_the_page_reach_core_wiki_mail
    # Not mailed as a member of the project: only a mention reaches him.
    User.find(2).update!(mail_notification: 'only_assigned')
    Member.where(user_id: 2).update_all(mail_notification: false)
    with_settings notified_events: %w[wiki_content_updated] do
      put '/projects/ecookbook/wiki/Another_page.json',
          params: { wiki_page: { text: "<p>#{mention(User.find(2))} see this</p>" } }.to_json,
          headers: json_headers('dlopper')
    end
    assert_response :no_content
    assert_includes recipients, 'jsmith@somenet.foo'

    ActionMailer::Base.deliveries.clear
    with_settings notified_events: %w[wiki_content_updated] do
      put '/projects/ecookbook/wiki/Another_page.json',
          params: { wiki_page: { text: "<p>#{mention(User.find(2))} see this again</p>" } }.to_json,
          headers: json_headers('dlopper')
    end
    refute_includes recipients, 'jsmith@somenet.foo', 'an edit that keeps a mention mails nobody anew'
  end

  def test_deleting_the_page_deletes_its_comments
    create_comment('dlopper', '<p>Bye</p>')
    WikiPage.find(2).destroy
    assert_equal 0, SprintlyWikiComment.count
  end

  # Wiki comments share core's `comments` table with news comments (no table of their own:
  # tenants are not migrated). Neither side sees or touches the other's rows.
  def test_news_comments_in_the_same_table_are_left_alone
    news_comments = Comment.where(commented_type: 'News').pluck(:id, :content)
    assert news_comments.any?, 'fixtures have news comments'
    comments_count = News.find(1).comments_count

    comment = create_comment('dlopper', '<p>Hello</p>')
    stored = Comment.unscoped.find(comment['id'])
    assert_equal ['WikiPage', 2], [stored.commented_type, stored.commented_id]
    assert_equal [comment['id']], SprintlyWikiComment.pluck(:id)

    WikiPage.find(2).destroy
    assert_equal news_comments, Comment.where(commented_type: 'News').pluck(:id, :content)
    assert_equal comments_count, News.find(1).reload.comments_count
  end

  def test_a_deleted_author_becomes_anonymous
    comment = create_comment('rhill', '<p>Left</p>')
    User.find(4).destroy
    assert_equal User.anonymous.id, SprintlyWikiComment.find(comment['id']).author_id
    get "#{URL}.json", params: { title: 'Another_page' }, headers: auth('jsmith')
    assert_response :success
    assert_equal 'Anonymous', body['comments'].first['author']['name']
  end

  def test_with_the_role_model_commenting_comes_with_wiki_view
    Sprintly::Store.clear!
    viewer = %w[wiki.view projects.view sections.wiki]
    post '/sprintly/import.json', headers: json_headers('admin'), params: {
      import: { roles: [
        { key: 'admin', name: 'Administrator', description: '', permissions: Sprintly::Permissions::APP_PERMISSIONS, preset: 'admin' },
        { key: 'viewer', name: 'Viewer', description: '', permissions: viewer, preset: 'viewer' }
      ], users: { '1' => ['admin'], '3' => ['viewer'] }, groups: {}, default_role: 'viewer', projects: {} }
    }.to_json
    assert_response :success
    comment = create_comment('dlopper', '<p>As a viewer</p>')
    refute comment['deletable'] && !comment['editable'], 'a viewer deletes only their own'
    other = SprintlyWikiComment.create!(page: WikiPage.find(2), author: User.find(1), content: '<p>Admin</p>')
    delete "#{URL}/#{other.id}.json", headers: auth('dlopper')
    assert_response :forbidden
  ensure
    Sprintly::Store.clear!
  end

  def test_reachable_through_the_extended_api_prefix
    create_comment('dlopper', '<p>Hi</p>')
    get "/extended_api#{URL}.json", params: { title: 'Another_page' }, headers: auth('jsmith')
    assert_response :success
    assert_equal 1, body['total_count']
  end
end

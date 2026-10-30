# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# SPR-523: watchers of a wiki page over the API.
#
# Fixtures: project 1 (ecookbook, public) has jsmith (2, Manager: may manage page watchers)
# and dlopper (3, Developer: may read pages, not manage watchers); rhill (4) is no member and
# reads it as Non member. Page 1 (CookBook_documentation) is watched by admin (1); project 2
# (onlinestore) is private.
class SprintlyWikiWatchersTest < Redmine::ApiTest::Base
  Sprintly = RedmineExtendedApi::Sprintly
  PASSWORDS = { 'dlopper' => 'foo', 'rhill' => 'rhill-secret' }.freeze
  URL = '/sprintly/projects/ecookbook/wiki/watchers.json'

  def setup
    super
    User.find(4).update!(password: 'rhill-secret', password_confirmation: 'rhill-secret')
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

  def page
    WikiPage.find(2)
  end

  def test_list_says_who_watches_and_whether_i_do
    get URL, params: { title: 'CookBook_documentation' }, headers: auth('dlopper')
    assert_response :success
    assert_equal [{ 'id' => 1, 'name' => 'Redmine Admin', 'type' => 'user' }], body['watchers']
    assert_equal false, body['watching']
    assert_equal true, body['can_watch']
    assert_equal false, body['can_manage']
  end

  def test_watch_and_unwatch_yourself
    post URL, params: { title: 'Another page' }.to_json, headers: json_headers('dlopper')
    assert_response :success
    assert body['watching']
    assert_equal [3], body['watchers'].map { |w| w['id'] }
    assert page.watched_by?(User.find(3))

    post URL, params: { title: 'Another_page' }.to_json, headers: json_headers('dlopper')
    assert_response :success
    assert_equal 1, page.watchers.count, 'watching twice keeps one watcher'

    delete URL, params: { title: 'Another_page' }, headers: auth('dlopper')
    assert_response :success
    refute body['watching']
    refute page.watched_by?(User.find(3))
  end

  def test_a_reader_who_is_no_member_may_watch_too
    post URL, params: { title: 'Another_page' }.to_json, headers: json_headers('rhill')
    assert_response :success
    assert page.watched_by?(User.find(4))
  end

  def test_others_need_the_watchers_permission
    post URL, params: { title: 'Another_page', user_id: 2 }.to_json, headers: json_headers('dlopper')
    assert_response :forbidden
    refute page.watched_by?(User.find(2))

    post URL, params: { title: 'Another_page', user_id: 3 }.to_json, headers: json_headers('jsmith')
    assert_response :success
    assert page.watched_by?(User.find(3))
    assert body['can_manage']

    delete URL, params: { title: 'Another_page', user_id: 3 }, headers: auth('dlopper')
    assert_response :success, 'removing yourself is yours to do'
    post URL, params: { title: 'Another_page', user_id: 3 }.to_json, headers: json_headers('jsmith')
    delete URL, params: { title: 'Another_page', user_id: 3 }, headers: auth('rhill')
    assert_response :forbidden
    delete URL, params: { title: 'Another_page', user_id: 3 }, headers: auth('jsmith')
    assert_response :success
    refute page.watched_by?(User.find(3))
  end

  def test_a_watcher_must_be_able_to_read_the_page
    page = WikiPage.find(3) # project 2, private: rhill is no member
    post '/sprintly/projects/onlinestore/wiki/watchers.json', params: { title: page.title, user_id: 4 }.to_json,
                                                              headers: json_headers('admin')
    assert_response :unprocessable_entity
    refute page.watched_by?(User.find(4))
  end

  def test_unknown_page_project_or_user
    get URL, params: { title: 'Nope' }, headers: auth('dlopper')
    assert_response :not_found
    get URL, headers: auth('dlopper')
    assert_response :not_found
    get '/sprintly/projects/nope/wiki/watchers.json', params: { title: 'Another_page' }, headers: auth('dlopper')
    assert_response :not_found
    post URL, params: { title: 'Another_page', user_id: 999 }.to_json, headers: json_headers('jsmith')
    assert_response :not_found
  end

  def test_a_page_you_cannot_read
    get '/sprintly/projects/onlinestore/wiki/watchers.json', params: { title: 'Start_page' }, headers: auth('rhill')
    assert_response :forbidden
    get URL, params: { title: 'Another_page' }
    assert_response :unauthorized
  end

  def test_a_renamed_page_is_found_through_its_redirect
    page.update!(title: 'Renamed_page', redirect_existing_links: true)
    post URL, params: { title: 'Another_page' }.to_json, headers: json_headers('dlopper')
    assert_response :success
    assert WikiPage.find(2).watched_by?(User.find(3))
  end

  def test_a_closed_project_is_read_only
    Project.find(1).close
    get URL, params: { title: 'Another_page' }, headers: auth('dlopper')
    assert_response :success
    refute body['can_watch']
    post URL, params: { title: 'Another_page' }.to_json, headers: json_headers('dlopper')
    assert_response :forbidden
  end

  def test_with_the_role_model_watching_comes_with_wiki_view
    Sprintly::Store.clear!
    viewer = %w[wiki.view projects.view sections.wiki]
    post '/sprintly/import.json', headers: json_headers('admin'), params: {
      import: { roles: [
        { key: 'admin', name: 'Administrator', description: '', permissions: Sprintly::Permissions::APP_PERMISSIONS, preset: 'admin' },
        { key: 'viewer', name: 'Viewer', description: '', permissions: viewer, preset: 'viewer' }
      ], users: { '1' => ['admin'], '3' => ['viewer'] }, groups: {}, default_role: 'viewer', projects: {} }
    }.to_json
    assert_response :success
    post URL, params: { title: 'Another_page' }.to_json, headers: json_headers('dlopper')
    assert_response :success
    assert page.watched_by?(User.find(3))
  ensure
    Sprintly::Store.clear!
  end

  def test_reachable_through_the_extended_api_prefix
    get "/extended_api#{URL}", params: { title: 'CookBook_documentation' }, headers: auth('dlopper')
    assert_response :success
    assert_equal [1], body['watchers'].map { |w| w['id'] }
  end
end

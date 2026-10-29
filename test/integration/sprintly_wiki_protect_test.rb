# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# SPR-522: locking a wiki page over the REST API.
#
# Fixtures used: project 1 (ecookbook, public); its page CookBook_documentation is protected
# and Another_page is not. jsmith (2) is a Manager and dlopper (3) a Developer there, both
# with protect_wiki_pages in the fixtures; Reporter (role 3) and Non member (4) have none.
class SprintlyWikiProtectTest < Redmine::ApiTest::Base
  Permissions = RedmineExtendedApi::Sprintly::Permissions
  PASSWORDS = { 'dlopper' => 'foo' }.freeze
  URL = '/sprintly/projects/ecookbook/wiki/Another_page/protect.json'

  def setup
    super
    RedmineExtendedApi::Sprintly::Store.clear!
  end

  def auth(login)
    credentials(login, PASSWORDS[login] || login)
  end

  def json_headers(login)
    auth(login).merge('CONTENT_TYPE' => 'application/json')
  end

  def body
    JSON.parse(response.body)
  end

  def lock(login, value, url = URL)
    put url, params: { wiki_page: { protected: value } }.to_json, headers: json_headers(login)
  end

  def test_reads_the_lock_and_what_the_user_may_do
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/protect.json', headers: auth('jsmith')
    assert_response :success
    assert_equal({ 'title' => 'CookBook_documentation', 'protected' => true, 'can_protect' => true, 'editable' => true },
                 body['wiki_page'])

    Role.find(2).remove_permission!(:protect_wiki_pages)
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/protect.json', headers: auth('dlopper')
    assert_response :success
    assert_equal true, body['wiki_page']['protected']
    assert_equal false, body['wiki_page']['can_protect']
    assert_equal false, body['wiki_page']['editable']
  end

  def test_locks_and_unlocks_a_page
    lock('jsmith', true)
    assert_response :success
    assert_equal true, body['wiki_page']['protected']
    assert WikiPage.find(2).protected?

    lock('jsmith', false)
    assert_response :success
    assert_equal false, body['wiki_page']['protected']
    refute WikiPage.find(2).reload.protected?
  end

  def test_a_locked_page_is_read_only_without_the_right_to_lock
    Role.find(2).remove_permission!(:protect_wiki_pages)
    lock('jsmith', true)
    assert_response :success

    put '/projects/ecookbook/wiki/Another_page.json',
        params: { wiki_page: { text: 'changed' } }.to_json, headers: json_headers('dlopper')
    assert_response :forbidden
    put '/projects/ecookbook/wiki/Another_page.json',
        params: { wiki_page: { text: 'changed' } }.to_json, headers: json_headers('jsmith')
    assert_response :no_content
  end

  def test_locking_needs_protect_wiki_pages
    Role.find(2).remove_permission!(:protect_wiki_pages)
    lock('dlopper', true)
    assert_response :forbidden
    refute WikiPage.find(2).reload.protected?
  end

  def test_rejects_a_missing_value_and_a_missing_page
    put URL, params: {}.to_json, headers: json_headers('jsmith')
    assert_response :unprocessable_entity
    lock('jsmith', true, '/sprintly/projects/ecookbook/wiki/No_such_page/protect.json')
    assert_response :not_found
  end

  def test_reading_the_lock_needs_view_wiki_pages
    get '/sprintly/projects/onlinestore/wiki/Start_page/protect.json', headers: auth('dlopper')
    assert_response :forbidden
  end

  def test_with_the_sprintly_role_model_wiki_protect_brings_the_lock
    assert_includes Permissions::APP_PERMISSIONS, 'wiki.protect'
    assert_equal %i[protect_wiki_pages], Permissions.derived_for(['wiki.protect'])

    post '/sprintly/import.json', headers: json_headers('admin'), params: {
      import: {
        roles: [
          { key: 'admin', name: 'Administrator', permissions: Permissions::APP_PERMISSIONS, preset: 'admin' },
          { key: 'developer', name: 'Developer', permissions: %w[wiki.view wiki.edit projects.view], preset: 'developer' }
        ],
        users: { '2' => ['admin'], '3' => ['developer'] }, groups: {}, default_role: 'developer', projects: {}
      }
    }.to_json
    assert_response :success

    lock('dlopper', true)
    assert_response :forbidden
    lock('jsmith', true)
    assert_response :success
    put '/projects/ecookbook/wiki/Another_page.json',
        params: { wiki_page: { text: 'changed' } }.to_json, headers: json_headers('dlopper')
    assert_response :forbidden

    developer = Role.givable.find_by!(name: 'Developer')
    put "/sprintly/roles/#{developer.id}.json", headers: json_headers('jsmith'),
        params: { role: { name: 'Developer', permissions: %w[wiki.view wiki.edit wiki.protect projects.view] } }.to_json
    assert_response :success
    lock('dlopper', false)
    assert_response :success
  end

  def test_reachable_through_the_extended_api_prefix
    get "/extended_api#{URL}", headers: auth('dlopper')
    assert_response :success
    lock('jsmith', true, "/extended_api#{URL}")
    assert_response :success
  end
end

# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# SPR-530: labels of wiki pages.
#
# Fixtures used: project 1 (ecookbook, public) owns wiki 1 (pages Another_page, Child_1, …);
# project 2 (onlinestore, private) owns wiki 2. jsmith (2) is a Manager of 1 and 2, dlopper (3)
# a Developer of project 1 only.
class SprintlyWikiLabelsTest < Redmine::ApiTest::Base
  Store = RedmineExtendedApi::Sprintly::Store
  Permissions = RedmineExtendedApi::Sprintly::Permissions

  def setup
    super
    Store.clear!
  end

  def put_labels(title, labels, project: 'ecookbook', login: 'jsmith', password: nil, prefix: '')
    body = { title: title }
    body[:labels] = labels unless labels == :none
    put "#{prefix}/sprintly/projects/#{project}/wiki/labels.json", params: body.to_json,
                                                                   headers: credentials(login, password).merge('CONTENT_TYPE' => 'application/json')
  end

  def get_labels(project: 'ecookbook', login: 'jsmith', password: nil)
    get "/sprintly/projects/#{project}/wiki/labels.json", headers: credentials(login, password)
  end

  def json
    JSON.parse(response.body)
  end

  def test_set_list_and_replace_labels
    put_labels 'Another page', ['How To', 'release', 'how-to', '  ', 'Нотатки!']
    assert_response :success
    assert_equal({ 'title' => 'Another_page', 'labels' => %w[how-to release нотатки] }, json)

    put_labels 'Child_1', ['release']
    assert_response :success

    get_labels
    assert_response :success
    assert_equal [{ 'title' => 'Another_page', 'labels' => %w[how-to release нотатки] },
                  { 'title' => 'Child_1', 'labels' => %w[release] }], json['labels']

    put_labels 'Another_page', %w[release decision]
    assert_response :success
    assert_equal %w[decision release], json['labels']

    put_labels 'Another_page', []
    assert_response :success
    assert_equal [], json['labels']
    get_labels
    assert_equal %w[Child_1], json['labels'].map { |p| p['title'] }
  end

  def test_through_the_proxy_prefix
    put_labels 'Another_page', ['x'], prefix: '/extended_api'
    assert_response :success
    get '/extended_api/sprintly/projects/ecookbook/wiki/labels.json', headers: credentials('jsmith')
    assert_response :success
    assert_equal [{ 'title' => 'Another_page', 'labels' => ['x'] }], json['labels']
  end

  def test_labels_follow_a_renamed_page_and_go_with_a_deleted_one
    put_labels 'Another_page', ['keep']
    page = WikiPage.find_by!(wiki_id: 1, title: 'Another_page')
    page.update!(title: 'Renamed_page')
    get_labels
    assert_equal [{ 'title' => 'Renamed_page', 'labels' => ['keep'] }], json['labels']

    page.reload.destroy
    assert_equal 0, SprintlyWikiPageLabel.where(wiki_page_id: page.id).count
  end

  # Tenants start from a prepared dump and run the plugin migrations on every container start.
  # A dump may hold the table without its schema_migrations row: running it again is a no-op
  # instead of an error that would stop the container.
  def test_the_migration_runs_again_on_a_database_that_has_the_table
    require File.expand_path('../../db/migrate/20261026120000_create_sprintly_wiki_page_labels', __dir__)
    put_labels 'Another_page', ['keep']
    ActiveRecord::Migration.suppress_messages { CreateSprintlyWikiPageLabels.new.migrate(:up) }
    get_labels
    assert_equal [{ 'title' => 'Another_page', 'labels' => ['keep'] }], json['labels']
  end

  def test_invalid_input
    put_labels 'Another_page', ['a' * 41]
    assert_response :unprocessable_entity
    put_labels 'Another_page', (1..21).map { |i| "l#{i}" }
    assert_response :unprocessable_entity
    put_labels 'Another_page', :none
    assert_response :unprocessable_entity
    put_labels 'No_such_page', ['x']
    assert_response :not_found
    get_labels project: 'subproject1', login: 'admin'
    assert_response :not_found
  end

  def test_reading_needs_view_and_writing_needs_edit
    get_labels project: 'onlinestore', login: 'dlopper', password: 'foo'
    assert_response :forbidden

    developer = Role.find(2)
    developer.remove_permission!(:edit_wiki_pages)
    get_labels login: 'dlopper', password: 'foo'
    assert_response :success
    put_labels 'Another_page', ['x'], login: 'dlopper', password: 'foo'
    assert_response :forbidden
  end

  def test_a_protected_page_only_for_who_may_protect
    WikiPage.find_by!(wiki_id: 1, title: 'Another_page').update!(protected: true)
    Role.find(2).remove_permission!(:protect_wiki_pages) # Developer
    put_labels 'Another_page', ['x'], login: 'dlopper', password: 'foo'
    assert_response :forbidden
    put_labels 'Another_page', ['x'] # jsmith, Manager: protect_wiki_pages
    assert_response :success
  end

  def test_with_the_role_model_creating_pages_is_not_enough
    roles = {
      'creator' => { name: 'Creator', permissions: %w[wiki.view wiki.create projects.view] },
      'editor' => { name: 'Editor', permissions: %w[wiki.view wiki.edit projects.view] }
    }
    post '/sprintly/import.json', params: { import: {
      roles: roles.map { |key, r| { key: key, name: r[:name], description: '', permissions: r[:permissions], preset: nil } } +
             [{ key: 'admin', name: 'Administrator', description: '', permissions: Permissions::APP_PERMISSIONS, preset: 'admin' }],
      users: { '2' => ['admin'], '3' => ['creator'] }, groups: {}, default_role: 'creator', projects: {}
    } }.to_json, headers: credentials('admin').merge('CONTENT_TYPE' => 'application/json')
    assert_response :success

    put_labels 'Another_page', ['x'], login: 'dlopper', password: 'foo'
    assert_response :forbidden

    put '/sprintly/assignments.json', params: { assignments: { users: { '3' => [Role.find_by!(name: 'Editor').id] } } }.to_json,
                                      headers: credentials('jsmith').merge('CONTENT_TYPE' => 'application/json')
    assert_response :success
    put_labels 'Another_page', ['x'], login: 'dlopper', password: 'foo'
    assert_response :success
  end
end

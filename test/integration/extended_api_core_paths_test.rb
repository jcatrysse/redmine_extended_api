# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# This plugin's accept_api_auth for create, update and destroy also opened core's own paths of
# the admin catalogues: an admin API key created, changed or deleted there and core answered
# 200, 302 or 406. Core's paths take an API key only for what core accepts (index, and show for
# roles); writes answer 403 like core without this plugin. /extended_api keeps them.
class ExtendedApiCorePathsTest < Redmine::ApiTest::Base
  def assert_core_write_refused(method, path, params = {})
    __send__(method, path, params: params, headers: credentials('admin'))
    assert_response :forbidden, "#{method.upcase} #{path}"
  end

  def test_roles_core_paths
    role = Role.find(1)
    unused = Role.create!(name: 'Unused role')
    assert_no_difference 'Role.count' do
      assert_core_write_refused :post, '/roles.json', role: {name: 'Core path role'}
      assert_core_write_refused :put, "/roles/#{role.id}.json", role: {name: 'Renamed on core path'}
      assert_core_write_refused :delete, "/roles/#{unused.id}.json"
    end
    assert_equal 'Manager', role.reload.name
    assert Role.find_by(id: unused.id)

    get "/roles/#{role.id}.json", headers: credentials('admin')
    assert_response :success
    get '/roles.json', headers: credentials('admin')
    assert_response :success

    put "/extended_api/roles/#{role.id}.json", params: {role: {name: 'Renamed'}}, headers: credentials('admin')
    assert_response :success
    assert_equal 'Renamed', role.reload.name
  end

  def test_trackers_core_paths
    tracker = Tracker.find(1)
    unused = Tracker.create!(name: 'Unused', default_status_id: 1)
    assert_no_difference 'Tracker.count' do
      assert_core_write_refused :post, '/trackers.json', tracker: {name: 'Core path tracker', default_status_id: 1}
      assert_core_write_refused :put, "/trackers/#{tracker.id}.json", tracker: {name: 'Renamed on core path'}
      assert_core_write_refused :delete, "/trackers/#{unused.id}.json"
    end
    assert_equal 'Bug', tracker.reload.name
    assert unused.class.find_by(id: unused.id)

    get '/trackers.json', headers: credentials('admin')
    assert_response :success

    put "/extended_api/trackers/#{tracker.id}.json", params: {tracker: {name: 'Renamed'}}, headers: credentials('admin')
    assert_response :success
    assert_equal 'Renamed', tracker.reload.name
  end

  def test_issue_statuses_core_paths
    status = IssueStatus.find(1)
    unused = IssueStatus.create!(name: 'Unused')
    assert_no_difference 'IssueStatus.count' do
      assert_core_write_refused :post, '/issue_statuses.json', issue_status: {name: 'Core path status'}
      assert_core_write_refused :put, "/issue_statuses/#{status.id}.json", issue_status: {name: 'Renamed on core path'}
      assert_core_write_refused :delete, "/issue_statuses/#{unused.id}.json"
    end
    assert_equal 'New', status.reload.name
    assert unused.class.find_by(id: unused.id)

    get '/issue_statuses.json', headers: credentials('admin')
    assert_response :success

    put "/extended_api/issue_statuses/#{status.id}.json", params: {issue_status: {name: 'Renamed'}},
                                                          headers: credentials('admin')
    assert_response :success
    assert_equal 'Renamed', status.reload.name
  end

  def test_enumerations_core_paths
    priority = IssuePriority.find(4)
    unused = IssuePriority.create!(name: 'Unused')
    assert_no_difference 'Enumeration.count' do
      assert_core_write_refused :post, '/enumerations.json', enumeration: {type: 'IssuePriority', name: 'Core path'}
      assert_core_write_refused :put, "/enumerations/#{priority.id}.json", enumeration: {name: 'Renamed on core path'}
      assert_core_write_refused :delete, "/enumerations/#{unused.id}.json"
    end
    assert_equal 'Low', priority.reload.name
    assert unused.class.find_by(id: unused.id)

    get '/enumerations/issue_priorities.json', headers: credentials('admin')
    assert_response :success

    put "/extended_api/enumerations/#{priority.id}.json", params: {enumeration: {name: 'Renamed'}},
                                                          headers: credentials('admin')
    assert_response :success
    assert_equal 'Renamed', priority.reload.name
  end
end

# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# The admin endpoints against a real Redmine, for the paths the doubles in
# spec/controller_patches_spec.rb cannot show (model callbacks that raise).
class ExtendedApiAdminEndpointsTest < Redmine::ApiTest::Base
  def test_destroy_issue_status_in_use_is_refused_without_server_error
    assert Issue.where(status_id: 1).exists?

    assert_no_difference 'IssueStatus.count' do
      delete '/extended_api/issue_statuses/1.json', headers: credentials('admin')
    end
    assert_response 422
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal ['Unable to delete issue status (This status is used by some issues)'], json['errors']
  end

  def test_destroy_unused_issue_status
    status = IssueStatus.create!(name: 'Unused')

    delete "/extended_api/issue_statuses/#{status.id}.json", headers: credentials('admin')
    assert_response :no_content
    assert_nil IssueStatus.find_by(id: status.id)
  end

  def test_destroy_issue_status_requires_admin
    status = IssueStatus.create!(name: 'Unused')

    delete "/extended_api/issue_statuses/#{status.id}.json", headers: credentials('jsmith')
    assert_response :forbidden
    assert IssueStatus.find_by(id: status.id)
  end

  # render_error answers an API format with an empty body, so these refusals
  # used to come back as a bare 422 without the reason.
  def test_destroy_tracker_in_use_is_refused_with_the_reason
    assert Issue.where(tracker_id: 1).exists?

    assert_no_difference 'Tracker.count' do
      delete '/extended_api/trackers/1.json', headers: credentials('admin')
    end
    assert_response 422
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['errors'].size
    # Redmine 7 names the projects (error_can_not_delete_tracker_html), 5.1 has no such key
    assert_match(/eCookbook|Unable to delete tracker/, json['errors'].first)
    assert_no_match(/<|>/, json['errors'].first)
  end

  def test_destroy_role_in_use_is_refused_with_the_reason
    assert Role.find(1).members.any?

    assert_no_difference 'Role.count' do
      delete '/extended_api/roles/1.xml', headers: credentials('admin')
    end
    assert_response 422
    assert_select 'errors error', text: I18n.t(:error_can_not_remove_role)
  end

  # Core's before_action renders the HTML type picker without a valid type.
  def test_create_custom_field_without_a_valid_type_is_refused_as_api_error
    [nil, 'NoSuchCustomField'].each do |type|
      assert_no_difference 'CustomField.count' do
        post '/extended_api/custom_fields.json',
             params: {type: type, custom_field: {name: 'No type', field_format: 'string'}}.compact,
             headers: credentials('admin')
      end
      assert_response 422
      assert_equal 'application/json', response.media_type
      assert_equal ['Type is invalid'], ActiveSupport::JSON.decode(response.body)['errors']
    end
  end

  def test_create_custom_field_with_a_type
    assert_difference 'IssueCustomField.count' do
      post '/extended_api/custom_fields.json',
           params: {type: 'IssueCustomField', custom_field: {name: 'With type', field_format: 'string'}},
           headers: credentials('admin')
    end
    assert_response :created
    assert_equal 'With type', ActiveSupport::JSON.decode(response.body)['custom_field']['name']
  end
end

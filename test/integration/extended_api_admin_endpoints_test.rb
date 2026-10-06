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
    assert_response :unprocessable_content
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
end

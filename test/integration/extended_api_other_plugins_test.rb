# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Next to other plugins that patch the same core methods. redmine_tags (branch master, the one
# Redmine 5.1 runs) loads after this plugin and builds an alias_method chain on
# Issue#safe_attributes=; while this plugin prepended its own safe_attributes=, every issue
# create and update ended in SystemStackError (500). Run with redmine_tags installed:
# RMP_EXTRA_PLUGINS="https://github.com/jcatrysse/redmine_tags.git@master" on 5.1-stable.
class ExtendedApiOtherPluginsTest < Redmine::ApiTest::Base
  def setup
    super
    skip 'needs redmine_tags (master) installed' unless Issue.method_defined?(:safe_attributes_without_safe_tags=)
  end

  def test_issue_create_and_update_next_to_an_alias_method_chain_on_safe_attributes
    assert_difference 'Issue.count', 2 do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Next to redmine_tags',
                            author_id: 2, created_on: '2020-01-02T03:04:05Z'}},
           headers: credentials('admin')
      assert_response :created
      post '/issues.json',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Core path next to redmine_tags'}},
           headers: credentials('admin')
      assert_response :created
    end

    issue = Issue.where(subject: 'Next to redmine_tags').first
    assert_equal 2, issue.author_id
    assert_equal Time.utc(2020, 1, 2, 3, 4, 5), issue.created_on.utc

    put "/extended_api/issues/#{issue.id}.json",
        params: {issue: {status_id: 5, notes: 'closed by import',
                         updated_on: '2021-05-06T07:08:09Z', closed_on: '2021-05-06T07:08:00Z'}},
        headers: credentials('admin')
    assert_response :success
    issue.reload
    assert issue.closed?
    assert_equal Time.utc(2021, 5, 6, 7, 8, 0), issue.closed_on.utc
    assert_equal Time.utc(2021, 5, 6, 7, 8, 9), issue.updated_on.utc
  end
end

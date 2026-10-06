# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# Runs against a real Redmine (database, callbacks, optimistic locking), where
# the specs in spec/ use doubles.
class ExtendedApiOverridesTest < Redmine::ApiTest::Base
  include ActiveJob::TestHelper

  def test_create_issue_as_admin_persists_author_and_timestamps
    assert_difference 'Issue.count' do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Imported',
                            author_id: 2, created_on: '2020-01-02T03:04:05Z',
                            updated_on: '2020-01-03T03:04:05Z'}},
           headers: credentials('admin')
    end
    assert_response :created

    issue = Issue.order(:id).last
    assert_equal 2, issue.author_id
    assert_equal Time.utc(2020, 1, 2, 3, 4, 5), issue.created_on.utc
    assert_equal Time.utc(2020, 1, 3, 3, 4, 5), issue.updated_on.utc
  end

  def test_create_issue_as_non_admin_ignores_overrides
    post '/extended_api/issues.json',
         params: {issue: {project_id: 1, tracker_id: 1, subject: 'Not imported',
                          author_id: 3, created_on: '2020-01-02T03:04:05Z'}},
         headers: credentials('jsmith')
    assert_response :created

    issue = Issue.order(:id).last
    assert_equal 2, issue.author_id
    assert issue.created_on > 1.hour.ago
  end

  def test_create_issue_through_core_path_ignores_overrides
    post '/issues.json',
         params: {issue: {project_id: 1, tracker_id: 1, subject: 'Core path',
                          author_id: 2, created_on: '2020-01-02T03:04:05Z'}},
         headers: credentials('admin')
    assert_response :created

    issue = Issue.order(:id).last
    assert_equal 1, issue.author_id
    assert issue.created_on > 1.hour.ago
  end

  def test_update_issue_as_admin_persists_updated_on_and_closed_on
    put '/extended_api/issues/1.json?notify=false',
        params: {issue: {status_id: 5, notes: 'closed by import',
                         updated_on: '2021-05-06T07:08:09Z', closed_on: '2021-05-06T07:08:00Z'}},
        headers: credentials('admin')
    assert_response :success

    issue = Issue.find(1)
    assert issue.closed?
    assert_equal Time.utc(2021, 5, 6, 7, 8, 9), issue.updated_on.utc
    assert_equal Time.utc(2021, 5, 6, 7, 8, 0), issue.closed_on.utc
  end

  def test_update_issue_twice_after_override_keeps_optimistic_locking_working
    put '/extended_api/issues/1.json',
        params: {issue: {subject: 'first', updated_on: '2021-05-06T07:08:09Z'}},
        headers: credentials('admin')
    assert_response :success
    put '/extended_api/issues/1.json',
        params: {issue: {subject: 'second'}},
        headers: credentials('admin')
    assert_response :success
    assert_equal 'second', Issue.find(1).subject
  end

  def test_update_issue_as_admin_persists_journal_overrides_and_returns_journal
    put '/extended_api/issues/1.json',
        params: {issue: {notes: 'imported note'},
                 journal: {user_id: 3, created_on: '2021-01-01T00:00:00Z'}},
        headers: credentials('admin')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    journal = Journal.find(json['journal']['id'])
    assert_equal 'imported note', journal.notes
    assert_equal 3, journal.user_id
    assert_equal Time.utc(2021, 1, 1), journal.created_on.utc
  end

  def test_upload_attachment_as_admin_persists_author_and_created_on
    set_tmp_attachments_directory
    post '/extended_api/uploads.json?filename=import.txt&attachment[author_id]=2&attachment[created_on]=2019-09-09T09:09:09Z',
         params: 'content',
         headers: {'CONTENT_TYPE' => 'application/octet-stream'}.merge(credentials('admin'))
    assert_response :created

    attachment = Attachment.order(:id).last
    assert_equal 2, attachment.author_id
    assert_equal Time.utc(2019, 9, 9, 9, 9, 9), attachment.created_on.utc
  end

  def test_create_issue_with_notify_false_sends_no_mail
    ActionMailer::Base.deliveries.clear
    with_settings notified_events: %w(issue_added) do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Silent'}},
           headers: credentials('admin')
      assert_response :created
    end
    assert_empty ActionMailer::Base.deliveries
  end

  # Redmine 7 webhooks render the issue when the transaction commits, after the
  # overrides were written, so a hook sees the imported author and dates.
  def test_webhook_payload_of_created_issue_carries_the_overrides
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    WebhookEndpointValidator.class_eval { @blocked_hosts = nil }
    hook = Webhook.create!(url: 'https://example.com/hook', user: User.find(1),
                           projects: [Project.find(1)], events: ['issue.created'], active: true)

    with_settings webhooks_enabled: '1' do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Imported with hook',
                            author_id: 2, created_on: '2020-01-02T03:04:05Z'}},
           headers: credentials('admin')
      assert_response :created
    end

    job = enqueued_jobs.detect { |j| j[:job] == WebhookJob }
    assert job, 'no webhook job enqueued'
    hook_id, json = job[:args]
    payload = ActiveSupport::JSON.decode(json)
    assert_equal hook.id, hook_id
    assert_equal 2, payload.dig('data', 'issue', 'author', 'id')
    assert_equal User.find(2).name, payload.dig('data', 'issue', 'author', 'name')
    assert_equal Time.utc(2020, 1, 2, 3, 4, 5), Time.zone.parse(payload.dig('data', 'issue', 'created_on')).utc
    # and the hook tells what is stored
    issue = Issue.find(payload.dig('data', 'issue', 'id'))
    assert_equal issue.author_id, payload.dig('data', 'issue', 'author', 'id')
    assert_equal issue.created_on.utc, Time.zone.parse(payload.dig('data', 'issue', 'created_on')).utc
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  # Unparseable times were stored as NULL (issues, attachments) or raised (journals, and
  # the Redmine 7 webhook payload); unknown users were stored as dangling ids.
  def test_create_issue_with_an_invalid_override_is_refused
    assert_no_difference 'Issue.count' do
      post '/extended_api/issues.json',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Bad date', author_id: 999, created_on: 'not a date'}},
           headers: credentials('admin')
    end
    assert_response :unprocessable_content
    assert_equal ['Author is invalid', 'Created is invalid'], ActiveSupport::JSON.decode(response.body)['errors']
  end

  def test_update_issue_with_an_invalid_journal_override_is_refused
    assert_no_difference 'Journal.count' do
      put '/extended_api/issues/1.json',
          params: {issue: {notes: 'bad journal date'}, journal: {user_id: 999, created_on: '2021-13-45'}},
          headers: credentials('admin')
    end
    assert_response :unprocessable_content
    assert_equal ['User is invalid', 'Created is invalid'], ActiveSupport::JSON.decode(response.body)['errors']
  end

  def test_upload_with_an_invalid_override_is_refused
    set_tmp_attachments_directory
    assert_no_difference 'Attachment.count' do
      post '/extended_api/uploads.json?filename=bad.txt&attachment[created_on]=garbage',
           params: 'content',
           headers: {'CONTENT_TYPE' => 'application/octet-stream'}.merge(credentials('admin'))
    end
    assert_response :unprocessable_content
    assert_equal ['Created is invalid'], ActiveSupport::JSON.decode(response.body)['errors']
  end

  def test_invalid_overrides_of_a_non_admin_are_ignored_as_before
    post '/extended_api/issues.json',
         params: {issue: {project_id: 1, tracker_id: 1, subject: 'Non admin', created_on: 'not a date', author_id: 999}},
         headers: credentials('jsmith')
    assert_response :created
    issue = Issue.order(:id).last
    assert_equal 2, issue.author_id
    assert_not_nil issue.created_on
  end
end

# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# Decision of Jan, 2026-10-07: notify=false on /extended_api silences the Redmine 7
# webhooks of that request too, not only the mail.
class ExtendedApiWebhooksTest < Redmine::ApiTest::Base
  include ActiveJob::TestHelper

  def setup
    super
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    WebhookEndpointValidator.class_eval { @blocked_hosts = nil }
    Webhook.create!(url: 'https://example.com/hook', user: User.find(1), projects: [Project.find(1)],
                    events: %w[issue.created issue.updated], active: true)
    clear_enqueued_jobs
  end

  def teardown
    ActiveJob::Base.queue_adapter = @original_adapter
    super
  end

  def hook_events
    enqueued_jobs.select { |j| j[:job] == WebhookJob }.map { |j| ActiveSupport::JSON.decode(j[:args][1])['type'] }
  end

  def create_issue(path, subject)
    with_settings webhooks_enabled: '1' do
      post path, params: {issue: {project_id: 1, tracker_id: 1, subject: subject}}, headers: credentials('admin')
    end
    assert_response :created
  end

  def test_create_with_notify_false_sends_no_webhook
    create_issue '/extended_api/issues.json?notify=false', 'Quiet'
    assert_equal [], hook_events
  end

  def test_create_without_notify_false_sends_the_webhook
    create_issue '/extended_api/issues.json', 'Loud'
    assert_equal ['issue.created'], hook_events
  end

  def test_update_with_send_notification_0_sends_no_webhook
    with_settings webhooks_enabled: '1' do
      put '/extended_api/issues/1.json?send_notification=0', params: {issue: {notes: 'quiet'}}, headers: credentials('admin')
      assert_response :success
      assert_equal [], hook_events

      put '/extended_api/issues/1.json', params: {issue: {notes: 'loud'}}, headers: credentials('admin')
      assert_response :success
      assert_equal ['issue.updated'], hook_events
    end
  end

  def test_relation_with_notify_false_sends_no_webhook
    with_settings webhooks_enabled: '1' do
      post '/extended_api/issues/2/relations.json?notify=false',
           params: {relation: {issue_to_id: 7, relation_type: 'relates'}}, headers: credentials('admin')
    end
    assert_response :created
    assert_equal [], hook_events
  end

  # the core path keeps core's behaviour: notify is not a core API parameter
  def test_core_path_ignores_notify_false
    create_issue '/issues.json?notify=false', 'Core'
    assert_equal ['issue.created'], hook_events
  end

  # the suppression lasts one request
  def test_next_request_sends_webhooks_again
    create_issue '/extended_api/issues.json?notify=false', 'Quiet'
    create_issue '/extended_api/issues.json', 'Loud'
    assert_equal ['issue.created'], hook_events
  end
end

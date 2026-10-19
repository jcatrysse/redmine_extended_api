# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# POST /extended_api/issues/:id/history.json (decision 41 of the Jira migration): imported
# status, assignee and priority changes as journals with their own user and time, written
# without saving the issue.
class ExtendedApiIssueHistoryTest < Redmine::ApiTest::Base
  include ActiveJob::TestHelper

  UPDATED_ON = Time.utc(2025, 1, 2, 3, 4, 5)
  CLOSED_ON = Time.utc(2025, 1, 1, 0, 0, 0)

  def setup
    super
    @delivery_method = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
    @issue = Issue.find(1)
    @issue.update_columns(updated_on: UPDATED_ON, closed_on: CLOSED_ON)
    Watcher.create!(watchable: @issue, user: User.find(3))
  end

  def teardown
    ActionMailer::Base.delivery_method = @delivery_method
    super
  end

  def history(journals, attachments: nil, as: 'admin', path: '/extended_api/issues/1/history.json')
    body = {journals: journals}
    body[:attachments] = attachments if attachments
    post path, params: body.to_json, headers: {'CONTENT_TYPE' => 'application/json'}.merge(credentials(as))
  end

  def status_change(user_id: 3, created_on: '2024-03-01T10:15:00Z', old_value: '1', value: '2')
    {user_id: user_id, created_on: created_on,
     details: [{property: 'attr', prop_key: 'status_id', old_value: old_value, value: value}]}
  end

  def test_history_stores_journals_and_details_with_their_user_and_time
    assert_difference 'Journal.count', 2 do
      history([
        {user_id: 3, created_on: '2024-03-01T10:15:00Z',
         details: [{property: 'attr', prop_key: 'status_id', old_value: '1', value: '2'},
                   {property: 'attr', prop_key: 'assigned_to_id', old_value: nil, value: '3'}]},
        {user_id: 2, created_on: '2024-03-02T11:00:00Z',
         details: [{property: 'attr', prop_key: 'priority_id', old_value: 4, value: 5},
                   {property: 'attr', prop_key: 'assigned_to_id', old_value: '3', value: nil}]}
      ])
    end
    assert_response :created

    json = ActiveSupport::JSON.decode(response.body)
    first, second = json['journal_ids'].map { |id| Journal.find(id) }
    assert_equal [], json['attachment_ids']
    assert_equal [3, Time.utc(2024, 3, 1, 10, 15), Time.utc(2024, 3, 1, 10, 15)],
                 [first.user_id, first.created_on.utc, first.updated_on.utc]
    assert_equal [2, Time.utc(2024, 3, 2, 11)], [second.user_id, second.created_on.utc]
    [first, second].each do |journal|
      assert_equal ['Issue', 1, '', false, nil],
                   [journal.journalized_type, journal.journalized_id, journal.notes, journal.private_notes, journal.updated_by_id]
    end
    assert_equal [%w[attr status_id 1 2], ['attr', 'assigned_to_id', nil, '3']],
                 first.details.order(:id).map { |d| [d.property, d.prop_key, d.old_value, d.value] }
    assert_equal [%w[attr priority_id 4 5], ['attr', 'assigned_to_id', '3', nil]],
                 second.details.order(:id).map { |d| [d.property, d.prop_key, d.old_value, d.value] }
  end

  def test_history_leaves_the_issue_and_its_watchers_alone
    watchers = @issue.watcher_user_ids.sort
    lock_version = @issue.reload.lock_version

    history([status_change(value: '5')])
    assert_response :created

    @issue.reload
    assert_equal [UPDATED_ON, CLOSED_ON, 1, lock_version],
                 [@issue.updated_on.utc, @issue.closed_on.utc, @issue.status_id, @issue.lock_version]
    assert_equal watchers, @issue.watcher_user_ids.sort
  end

  def test_history_sends_no_mail_and_no_webhook
    hook = nil
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    if defined?(Webhook)
      WebhookEndpointValidator.class_eval { @blocked_hosts = nil }
      hook = Webhook.create!(url: 'https://example.com/hook', user: User.find(1),
                             projects: [Project.find(1)], events: ['issue.updated'], active: true)
    end
    clear_enqueued_jobs

    settings = {notified_events: %w(issue_updated issue_status_updated issue_assigned_to_updated issue_priority_updated)}
    settings[:webhooks_enabled] = '1' if defined?(Webhook) # no webhooks before Redmine 7
    with_settings settings do
      history([status_change])
      assert_response :created
    end

    # mail is enqueued (deliver_later) or delivered, webhooks are enqueued (WebhookJob)
    assert_empty enqueued_jobs
    assert_empty ActionMailer::Base.deliveries

    # control: the same change as an issue update is seen by this setup
    with_settings settings do
      put '/extended_api/issues/1.json', params: {issue: {status_id: 2}}, headers: credentials('admin')
      assert_response :success
    end
    assert enqueued_jobs.any? { |job| job[:job].to_s =~ /Mail|Webhook/ }, enqueued_jobs.inspect
  ensure
    hook&.destroy
    ActiveJob::Base.queue_adapter = original_adapter
  end

  # Redmine's history is ordered by created_on, then id: an imported change before and one
  # after an existing comment show around it, though both were written after it.
  def test_history_tab_shows_the_changes_at_their_own_time_around_a_comment
    comment = Journal.create!(journalized: @issue, user: User.find(2), notes: 'Comment in between')
    comment.update_columns(created_on: Time.utc(2024, 3, 2), updated_on: Time.utc(2024, 3, 2))

    history([status_change(created_on: '2024-03-01T10:00:00Z', old_value: '1', value: '2'),
             status_change(created_on: '2024-03-03T10:00:00Z', old_value: '2', value: '3')])
    assert_response :created
    before, after = ActiveSupport::JSON.decode(response.body)['journal_ids']

    get '/extended_api/issues/1.json?include=journals', headers: credentials('admin')
    ids = ActiveSupport::JSON.decode(response.body)['issue']['journals'].map { |j| j['id'] }
    assert_equal [before, comment.id, after], ids.select { |id| [before, comment.id, after].include?(id) }

    log_user('admin', 'admin')
    get '/issues/1'
    assert_response :success
    html_ids = css_select('#history div.journal').map { |div| div['id'].to_s.delete_prefix('change-').to_i }
    assert_equal [before, comment.id, after], html_ids.select { |id| [before, comment.id, after].include?(id) }
    assert_select "#change-#{before}", text: /Status changed from New to Assigned/
    assert_select "#change-#{after}", text: /Status changed from Assigned to Resolved/
  end

  def test_history_with_an_upload_attaches_it_with_its_author_and_time_and_no_journal
    set_tmp_attachments_directory
    post '/extended_api/uploads.json?filename=upload.json', params: '{"jira":"history"}',
         headers: {'CONTENT_TYPE' => 'application/octet-stream'}.merge(credentials('admin'))
    assert_response :created
    token = ActiveSupport::JSON.decode(response.body)['upload']['token']

    assert_difference 'Journal.count', 1 do
      history([status_change],
              attachments: [{token: token, filename: 'jira-history.json', content_type: 'application/json',
                             description: 'Jira history', author_id: 2, created_on: '2024-05-02T08:00:00Z'}])
    end
    assert_response :created

    attachment = Attachment.find(ActiveSupport::JSON.decode(response.body)['attachment_ids'].first)
    assert_equal [@issue, 2, Time.utc(2024, 5, 2, 8), 'jira-history.json', 'application/json', 'Jira history'],
                 [attachment.container, attachment.author_id, attachment.created_on.utc,
                  attachment.filename, attachment.content_type, attachment.description]
    assert_equal UPDATED_ON, @issue.reload.updated_on.utc
    assert_not JournalDetail.where(property: 'attachment', prop_key: attachment.id.to_s).exists?
  end

  def test_history_as_non_admin_is_refused
    assert_no_difference 'Journal.count' do
      history([status_change], as: 'jsmith')
    end
    assert_response :forbidden
    assert_include 'You are not authorized to access this page.', ActiveSupport::JSON.decode(response.body)['errors']
  end

  def test_history_without_credentials_is_unauthorized
    post '/extended_api/issues/1/history.json', params: {journals: [status_change]}.to_json,
         headers: {'CONTENT_TYPE' => 'application/json'}
    assert_response :unauthorized
  end

  def test_history_on_the_core_path_is_not_found
    assert_no_difference 'Journal.count' do
      history([status_change], path: '/issues/1/history.json')
    end
    assert_response :not_found
  end

  def test_history_in_an_archived_project_is_refused
    Project.find(1).update_column(:status, Project::STATUS_ARCHIVED)
    assert_no_difference 'Journal.count' do
      history([status_change])
    end
    assert_response :forbidden
  end

  # an import may close its projects before it writes their history
  def test_history_in_a_closed_project_is_written
    Project.find(1).update_column(:status, Project::STATUS_CLOSED)
    assert_difference 'Journal.count', 1 do
      history([status_change])
    end
    assert_response :created
  end

  def test_history_of_an_unknown_issue_is_not_found
    history([status_change], path: '/extended_api/issues/999999/history.json')
    assert_response :not_found
  end

  def test_history_refuses_invalid_input_and_stores_nothing
    detail = ->(attrs) { status_change.merge(details: [{property: 'attr', prop_key: 'status_id', old_value: '1', value: '2'}.merge(attrs)]) }
    cases = {
      'empty list' => [[], 'History is invalid'],
      'no details' => [[status_change.merge(details: [])], 'Details is invalid'],
      'other property' => [[detail.call(property: 'cf', prop_key: '1')], 'Property is invalid'],
      'other key' => [[detail.call(prop_key: 'subject', value: 'x')], 'Prop key is invalid'],
      'unknown status' => [[detail.call(value: '999')], 'Status is invalid'],
      'unknown old status' => [[detail.call(old_value: '999')], 'Status is invalid'],
      'status removed' => [[detail.call(value: nil)], 'Status is invalid'],
      'unknown assignee' => [[detail.call(prop_key: 'assigned_to_id', value: '999')], 'Assignee is invalid'],
      'unknown priority' => [[detail.call(prop_key: 'priority_id', old_value: '4', value: '999')], 'Priority is invalid'],
      'unknown user' => [[status_change(user_id: 999)], 'User is invalid'],
      'no user' => [[status_change(user_id: nil)], 'User is invalid'],
      'unparseable time' => [[status_change(created_on: 'yesterday-ish')], 'Created is invalid'],
      'no time' => [[status_change(created_on: nil)], 'Created is invalid'],
      'notes' => [[status_change.merge(notes: 'a comment')], 'Notes is invalid'],
      'private notes' => [[status_change.merge(private_notes: true)], 'Notes is invalid'],
      'second journal invalid' => [[status_change, status_change(user_id: 999)], 'User is invalid']
    }

    cases.each do |name, (journals, message)|
      assert_no_difference ['Journal.count', 'JournalDetail.count'], name do
        history(journals)
      end
      assert_response :unprocessable_entity, name
      assert_include message, ActiveSupport::JSON.decode(response.body)['errors'], name
    end
  end

  def test_history_refuses_an_invalid_attachment_and_stores_nothing
    cases = {
      'unknown token' => [{token: '999.abc', author_id: 2, created_on: '2024-05-02T08:00:00Z'}, 'Token is invalid'],
      'unknown author' => [{token: '999.abc', author_id: 999, created_on: '2024-05-02T08:00:00Z'}, 'Author is invalid'],
      'unparseable time' => [{token: '999.abc', author_id: 2, created_on: 'never'}, 'Created is invalid']
    }
    cases.each do |name, (attachment, message)|
      assert_no_difference ['Journal.count', 'JournalDetail.count'], name do
        history([status_change], attachments: [attachment])
      end
      assert_response :unprocessable_entity, name
      assert_include message, ActiveSupport::JSON.decode(response.body)['errors'], name
    end
  end
end

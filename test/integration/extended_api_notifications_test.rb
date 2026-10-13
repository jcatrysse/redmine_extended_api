# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# notify=false must silence the request that asks for it, and nothing else:
# Mailer.with_deliveries(false) switched deliveries off for the whole process,
# so mail of other requests (Puma threads, async mail jobs) delivered during an
# import request was dropped.
class ExtendedApiNotificationsTest < Redmine::ApiTest::Base
  include ActiveJob::TestHelper

  # A mail that needs no database, so another thread can send it while the
  # request holds the test connection.
  class ProbeMailer < ActionMailer::Base
    def probe
      mail(to: 'probe@example.net', from: 'redmine@example.net', subject: 'probe', body: 'probe')
    end
  end

  def setup
    super
    # config/configuration.yml may route mail elsewhere (files) for every environment
    @delivery_method = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    ActionMailer::Base.delivery_method = @delivery_method
    super
  end

  # Runs action once, in the request thread, when the issue row is inserted.
  def during_issue_insert(action)
    done = false
    callback = lambda do |*, payload|
      next if done || !payload[:sql].to_s.start_with?('INSERT INTO "issues"', 'INSERT INTO `issues`')

      done = true
      action.call
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
  end

  def test_notify_false_does_not_drop_mail_delivered_by_another_thread
    during_issue_insert(-> { Thread.new { ProbeMailer.probe.deliver_now }.join }) do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Quiet import'}},
           headers: credentials('admin')
    end
    assert_response :created
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal ['probe@example.net'], ActionMailer::Base.deliveries.first.to
  end

  def test_notify_false_drops_mail_delivered_in_the_request_thread
    during_issue_insert(-> { ProbeMailer.probe.deliver_now }) do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Quiet import'}},
           headers: credentials('admin')
    end
    assert_response :created
    assert_empty ActionMailer::Base.deliveries
  end

  # The mail jobs are counted, not the deliveries: the inline test adapter runs a
  # job only when the transaction commits, which a transactional test never does.
  def test_notify_false_enqueues_no_issue_mail_and_without_it_one_is_enqueued
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    # Mailer::DeliveryJob on Redmine 7, ActionMailer's own job on 5.1
    issue_mails = -> { enqueued_jobs.count { |j| j[:job].to_s.include?('DeliveryJob') && j[:args][1] == 'issue_add' } }

    with_settings notified_events: %w(issue_added) do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Quiet', assigned_to_id: 3}},
           headers: credentials('admin')
      assert_response :created
      assert_equal 0, issue_mails.call

      post '/extended_api/issues.json',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Loud', assigned_to_id: 3}},
           headers: credentials('admin')
      assert_response :created
      assert_operator issue_mails.call, :>, 0
    end
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  def test_relation_with_notify_false_does_not_drop_mail_of_another_thread
    delivered = nil
    callback = lambda do |*, payload|
      next if delivered || !payload[:sql].to_s.start_with?('INSERT INTO "issue_relations"', 'INSERT INTO `issue_relations`')

      delivered = Thread.new { ProbeMailer.probe.deliver_now }.join
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      post '/extended_api/issues/2/relations.json?notify=false',
           params: {relation: {issue_to_id: 7, relation_type: 'relates'}},
           headers: credentials('admin')
    end
    assert_response :created
    assert_equal [['probe@example.net']], ActionMailer::Base.deliveries.map(&:to)
  end
end

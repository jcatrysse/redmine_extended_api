# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/api_helpers'
require_relative '../lib/redmine_extended_api/patches/notification_suppression_patch'
require_relative '../lib/redmine_extended_api/patches/issues_controller_patch'

RSpec.describe RedmineExtendedApi::Patches::IssuesControllerPatch do
  let(:admin_user) { instance_double('User', admin?: true) }
  let(:non_admin_user) { instance_double('User', admin?: false) }

  let(:controller_class) do
    Class.new do
      include RedmineExtendedApi::Patches::ApiHelpers

      attr_accessor :params, :thread_snapshot, :journal_snapshot, :extended_enabled, :request

      def initialize
        @extended_enabled = true
      end

      def extended_api_request?
        extended_enabled
      end

      def api_request?
        true
      end

      def create
        @thread_snapshot = Thread.current[:redmine_extended_api_issue_overrides]
        @journal_snapshot = Thread.current[:redmine_extended_api_journal_overrides]

        # Simuleer hoe Redmine een notificatie triggert
        Issue.new.send_notification

        :base_create
      end

      def update
        @thread_snapshot = Thread.current[:redmine_extended_api_issue_overrides]
        @journal_snapshot = Thread.current[:redmine_extended_api_journal_overrides]

        # Simuleer notificatie op journal (notes)
        Journal.new.send_notification

        :base_update
      end
    end.tap { |klass| klass.prepend described_class }
  end

  let(:controller) { controller_class.new }

  before do
    stub_const('User', Class.new do
      class << self
        attr_accessor :current
      end
    end)

    User.current = admin_user

    stub_const('Issue', Class.new do
      class << self
        attr_accessor :record_timestamps, :record_timestamps_calls
      end

      self.record_timestamps_calls = []
      self.record_timestamps = true

      def self.record_timestamps=(value)
        self.record_timestamps_calls << value
        @record_timestamps = value
      end

      def self.notif_calls
        @notif_calls ||= 0
      end

      def self.reset_notif_calls!
        @notif_calls = 0
      end

      def send_notification
        self.class.instance_variable_set(:@notif_calls, self.class.notif_calls + 1)
      end
    end)

    stub_const('Journal', Class.new do
      class << self
        attr_accessor :record_timestamps, :record_timestamps_calls
      end

      self.record_timestamps_calls = []
      self.record_timestamps = true

      def self.record_timestamps=(value)
        self.record_timestamps_calls << value
        @record_timestamps = value
      end

      def self.notif_calls
        @notif_calls ||= 0
      end

      def self.reset_notif_calls!
        @notif_calls = 0
      end

      def send_notification
        self.class.instance_variable_set(:@notif_calls, self.class.notif_calls + 1)
      end
    end)

    stub_const('Mailer', Class.new do
      def self.with_deliveries(*)
        yield
      end
    end)

    Issue.include RedmineExtendedApi::Patches::NotificationSuppressionPatch
    Journal.include RedmineExtendedApi::Patches::NotificationSuppressionPatch

    controller.request = double('Request', env: {
      'redmine_extended_api.original_script_name' => '',
      'redmine_extended_api.original_path_info' => '/extended_api/issues.json'
    })

    Issue.reset_notif_calls!
    Journal.reset_notif_calls!
  end

  after do
    Thread.current[:redmine_extended_api_issue_overrides] = nil
    Thread.current[:redmine_extended_api_journal_overrides] = nil

    Issue.record_timestamps_calls = []
    Issue.record_timestamps = true

    Journal.record_timestamps_calls = []
    Journal.record_timestamps = true

    Issue.reset_notif_calls!
    Journal.reset_notif_calls!
  end

  it 'wraps create with notification suppression and timestamp control' do
    controller.params = {
      issue: { author_id: 5, created_on: '2020-01-01', closed_on: '2020-03-03' },
      notify: '0'
    }

    expect(Mailer).to receive(:with_deliveries).with(false).and_yield

    expect(controller.create).to eq(:base_create)
    expect(controller.thread_snapshot).to eq(author_id: 5, created_on: '2020-01-01', closed_on: '2020-03-03')
    expect(controller.journal_snapshot).to eq({})
    expect(Issue.record_timestamps_calls).to eq([false, true])
    expect(Thread.current[:redmine_extended_api_issue_overrides]).to be_nil
  end

  it 'suppresses notifications when notify is boolean false' do
    controller.params = { issue: { subject: 'x' }, notify: false }

    controller.create
    expect(Issue.notif_calls).to eq(0)
  end

  it 'suppresses notifications when send_notification is 0' do
    controller.params = { issue: { subject: 'x' }, send_notification: '0' }

    controller.create
    expect(Issue.notif_calls).to eq(0)
  end

  it 'falls back to the base action when the request is not extended' do
    controller.params = { issue: { subject: 'Native' }, notify: '0' }
    allow(controller).to receive(:extended_api_request?).and_return(false)

    expect(Mailer).not_to receive(:with_deliveries)

    expect(controller.create).to eq(:base_create)
    expect(controller.thread_snapshot).to be_nil
    expect(controller.journal_snapshot).to be_nil
    expect(Issue.record_timestamps_calls).to be_empty
  end

  it 'leaves timestamps intact when no issue override is requested' do
    controller.params = { issue: { subject: 'Keep timestamps' } }

    expect(controller.update).to eq(:base_update)
    expect(Issue.record_timestamps_calls).to be_empty
  end

  it 'captures journal overrides and disables journal timestamps when provided' do
    controller.params = { journal: { user_id: 8, updated_on: '2020-02-01' }, send_notifications: 'false' }

    expect(controller.update).to eq(:base_update)
    expect(controller.journal_snapshot).to eq(user_id: 8, updated_on: '2020-02-01')
    expect(Journal.record_timestamps_calls).to eq([])
    expect(Thread.current[:redmine_extended_api_journal_overrides]).to be_nil
  end

  it 'accepts nested journal override attributes under the issue payload' do
    controller.params = { issue: { journal: { 'updated_by_id' => 12 } }, send_notifications: '0' }

    expect(controller.update).to eq(:base_update)
    expect(controller.journal_snapshot).to eq(updated_by_id: 12)
  end

  it 'ignores override-related controls for non-admin users' do
    User.current = non_admin_user
    controller.params = { issue: { journal: { 'updated_on' => '2020-02-02' } }, notify: '0' }

    expect(controller.update).to eq(:base_update)
    expect(controller.journal_snapshot).to be_nil
    expect(Journal.record_timestamps_calls).to be_empty
    expect(Thread.current[:redmine_extended_api_journal_overrides]).to be_nil
    expect(Thread.current[:redmine_extended_api_issue_overrides]).to be_nil
  end
end

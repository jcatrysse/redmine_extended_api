# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/api_helpers'
require_relative '../lib/redmine_extended_api/patches/issues_controller_patch'
require_relative '../lib/redmine_extended_api/patches/issue_patch'

RSpec.describe RedmineExtendedApi::Patches::IssuesControllerPatch do
  let(:issue_class) do
    Class.new do
      class << self
        attr_accessor :record_timestamps, :record_timestamps_calls
      end

      self.record_timestamps_calls = []
      self.record_timestamps = true

      def self.record_timestamps=(value)
        self.record_timestamps_calls << value
        @record_timestamps = value
      end
    end
  end

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
        :base_create
      end

      def update
        @thread_snapshot = Thread.current[:redmine_extended_api_issue_overrides]
        @journal_snapshot = Thread.current[:redmine_extended_api_journal_overrides]
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

    User.current = double('User', admin?: true)

    stub_const('Issue', issue_class)
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
    end)
    stub_const('Mailer', Class.new do
      def self.with_deliveries(*)
        yield
      end
    end)

    controller.request = double('Request', env: {
                                  'redmine_extended_api.original_script_name' => '',
                                  'redmine_extended_api.original_path_info' => '/extended_api/issues.json'
                                })
  end

  after do
    Thread.current[:redmine_extended_api_issue_overrides] = nil
    Thread.current[:redmine_extended_api_journal_overrides] = nil
    Issue.record_timestamps_calls = []
    Issue.record_timestamps = true
    Journal.record_timestamps_calls = []
    Journal.record_timestamps = true
    User.current = nil
  end

  it 'wraps create with notification suppression and timestamp control' do
    controller.params = {issue: {author_id: 5, created_on: '2020-01-01', closed_on: '2020-03-03'}, notify: '0'}

    expect(Mailer).to receive(:with_deliveries).with(false).and_yield

    expect(controller.create).to eq(:base_create)
    expect(controller.thread_snapshot).to eq(author_id: 5, created_on: '2020-01-01', closed_on: '2020-03-03')
    expect(controller.journal_snapshot).to eq({})
    expect(Issue.record_timestamps_calls).to eq([false, true])
    expect(Thread.current[:redmine_extended_api_issue_overrides]).to be_nil
  end

  it 'falls back to the base action when the request is not extended' do
    controller.params = {issue: {subject: 'Native'}, notify: '0'}
    allow(controller).to receive(:extended_api_request?).and_return(false)

    expect(Mailer).not_to receive(:with_deliveries)

    expect(controller.create).to eq(:base_create)
    expect(controller.thread_snapshot).to be_nil
    expect(controller.journal_snapshot).to be_nil
    expect(Issue.record_timestamps_calls).to be_empty
  end

  it 'leaves timestamps intact when no override is requested' do
    controller.params = {issue: {subject: 'Keep timestamps'}}

    expect(controller.update).to eq(:base_update)
    expect(Issue.record_timestamps_calls).to be_empty
  end

  it 'captures journal overrides and disables journal timestamps when provided' do
    controller.params = {journal: {user_id: 8, updated_on: '2020-02-01'}, send_notifications: 'false'}

    expect(controller.update).to eq(:base_update)
    expect(controller.journal_snapshot).to eq(user_id: 8, updated_on: '2020-02-01')
    expect(Journal.record_timestamps_calls).to eq([])
    expect(Thread.current[:redmine_extended_api_journal_overrides]).to be_nil
  end

  it 'accepts nested journal override attributes under the issue payload' do
    controller.params = {issue: {journal: {'updated_by_id' => 12}}, send_notifications: '0'}

    expect(controller.update).to eq(:base_update)
    expect(controller.journal_snapshot).to eq(updated_by_id: 12)
  end
end

RSpec.describe RedmineExtendedApi::Patches::IssuePatch do
  let(:issue_class) do
    Class.new do
      attr_reader :assigned_attributes, :safe_attributes_payload, :init_journal_args, :current_journal
      attr_accessor :notify

      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.after_save(*); end

      def init_journal(user, notes = '')
        @init_journal_args = [user, notes]
        @current_journal = Journal.new
      end

      def assign_attributes(attrs)
        @assigned_attributes ||= {}
        @assigned_attributes.merge!(attrs)
      end

      def safe_attributes=(attrs, user = nil)
        @safe_attributes_payload = attrs
      end
      end.tap { |klass| klass.include described_class }
    end

  let(:issue) { issue_class.new }
  let(:admin_user) { double('User', admin?: true) }
  let(:non_admin_user) { double('User', admin?: false) }
  let(:journal_class) do
    Class.new do
      attr_reader :attributes

      def initialize
        @attributes = {}
      end

      def assign_attributes(attrs)
        @attributes.merge!(attrs)
      end
    end
  end

  before do
    stub_const('User', Class.new do
      class << self
        attr_accessor :current
      end
    end)
    stub_const('Journal', journal_class)
  end

  after do
    Thread.current[:redmine_extended_api_issue_overrides] = nil
    Thread.current[:redmine_extended_api_journal_overrides] = nil
    Thread.current[:redmine_extended_api_suppress_notifications] = nil
  end

  it 'applies override attributes for admins' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = {
      author_id: 3,
      created_on: '2020-01-01',
      updated_on: '2020-01-02',
      closed_on: '2020-01-03',
      other: 'ignored'
    }

    issue.safe_attributes=({subject: 'New'})

    expect(issue.assigned_attributes).to eq(author_id: 3, created_on: '2020-01-01', updated_on: '2020-01-02', closed_on: '2020-01-03')
  end

  it 'ignores overrides for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = {author_id: 3}

    issue.safe_attributes=({subject: 'New'})

    expect(issue.assigned_attributes).to be_nil
  end

  it 'applies journal overrides when initialising a journal as an admin' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = {user_id: 9, updated_by_id: 4, updated_on: '2020-02-02'}

    issue.init_journal(admin_user, 'note')

    expect(issue.init_journal_args).to eq([admin_user, 'note'])
    expect(issue.current_journal.attributes).to eq(user_id: 9, updated_by_id: 4, updated_on: '2020-02-02')
  end
end

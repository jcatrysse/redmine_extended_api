# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/api_helpers'
require_relative '../lib/redmine_extended_api/patches/notification_suppression_patch'
require_relative '../lib/redmine_extended_api/patches/issue_relations_controller_patch'

RSpec.describe RedmineExtendedApi::Patches::IssueRelationsControllerPatch do
  let(:controller_class) do
    Class.new do
      include RedmineExtendedApi::Patches::ApiHelpers

      attr_accessor :params, :extended_enabled, :request

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
        IssueRelation.new.send_notification
        :base_create
      end

      def destroy
        IssueRelation.new.send_notification
        :base_destroy
      end
    end.tap { |klass| klass.prepend described_class }
  end

  let(:controller) { controller_class.new }

  before do
    stub_const('IssueRelation', Class.new do
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

    IssueRelation.include RedmineExtendedApi::Patches::NotificationSuppressionPatch

    controller.request = double('Request', env: {
      'redmine_extended_api.original_script_name' => '',
      'redmine_extended_api.original_path_info' => '/extended_api/issues/1/relations.json'
    })

    IssueRelation.reset_notif_calls!
  end

  after do
    Thread.current[:redmine_extended_api_suppress_notifications] = nil
    IssueRelation.reset_notif_calls!
  end

  it 'suppresses relation notifications when notify=false on create' do
    controller.params = { relation: { issue_to_id: 2 }, notify: '0' }

    expect(Mailer).to receive(:with_deliveries).with(false).and_yield

    expect(controller.create).to eq(:base_create)
    expect(IssueRelation.notif_calls).to eq(0)
  end

  it 'suppresses relation notifications when notify=false on destroy' do
    controller.params = { notify: false }

    expect(Mailer).to receive(:with_deliveries).with(false).and_yield

    expect(controller.destroy).to eq(:base_destroy)
    expect(IssueRelation.notif_calls).to eq(0)
  end

  it 'does not suppress notifications for non-extended requests' do
    controller.params = { notify: '0' }
    controller.extended_enabled = false
    controller.request = double('Request', env: {
      'redmine_extended_api.original_script_name' => '',
      'redmine_extended_api.original_path_info' => '/issues/1/relations.json'
    })

    expect(Mailer).not_to receive(:with_deliveries)

    expect(controller.create).to eq(:base_create)
    expect(IssueRelation.notif_calls).to eq(1)
  end
end

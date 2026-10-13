# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/notification_suppression_patch'

RSpec.describe RedmineExtendedApi::Patches::NotificationSuppressionPatch do
  # like core: send_notification (private) sends only when notify? is true
  def self.record_class
    Class.new do
      include FakeNotifyingRecord

      def notif_calls
        @calls || 0
      end

      private

      def send_notification(*)
        @calls = (@calls || 0) + 1 if notify?
      end
    end
  end

  let(:issue_class) { self.class.record_class }
  let(:journal_class) { self.class.record_class }

  before do
    stub_const('Issue', issue_class)
    stub_const('Journal', journal_class)

    # included as init.rb does
    Issue.include(described_class)
    Journal.include(described_class)
  end

  after do
    Thread.current[:redmine_extended_api_suppress_notifications] = nil
  end

  it 'does not suppress notifications when the thread flag is not set (Issue)' do
    issue = Issue.new
    issue.save
    expect(issue.notif_calls).to eq(1)
  end

  it 'suppresses notifications when the thread flag is set (Issue)' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    issue = Issue.new
    issue.save
    expect(issue.notif_calls).to eq(0)
  end

  it 'suppresses notifications when the thread flag is set (Journal)' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    journal = Journal.new
    journal.save
    expect(journal.notif_calls).to eq(0)
  end

  it 'does not leak suppression between examples' do
    issue = Issue.new
    issue.save
    expect(issue.notif_calls).to eq(1)
  end

  it 'does not define send_notification, which stays private as it is in Redmine' do
    expect(described_class.instance_methods + described_class.private_instance_methods).not_to include(:send_notification)
    expect(Issue.new.respond_to?(:send_notification)).to be(false)
    expect(Issue.private_method_defined?(:send_notification)).to be(true)
  end

  # redmine_stealth prepends send_notification; an alias_method chain of ours recursed next to it.
  context 'with another plugin that prepends send_notification' do
    let(:other_plugin) do
      Module.new do
        def other_calls
          @other_calls
        end

        private

        def send_notification(*)
          @other_calls = (@other_calls || 0) + 1
          super
        end
      end
    end

    it 'runs the other plugin and the original once' do
      Issue.prepend(other_plugin)

      issue = Issue.new
      expect { issue.save }.not_to raise_error
      expect([issue.other_calls, issue.notif_calls]).to eq([1, 1])
    end

    it 'still suppresses' do
      Issue.prepend(other_plugin)
      Thread.current[:redmine_extended_api_suppress_notifications] = true

      issue = Issue.new
      issue.save
      expect([issue.other_calls, issue.notif_calls]).to eq([1, 0])
    end
  end

  # On Redmine 5.1/6.1 a plugin loaded after this one may alias_method-chain send_notification;
  # when this patch prepended send_notification, that chain called itself (SystemStackError).
  context 'with another plugin that alias_method-chains send_notification after this one' do
    before do
      Issue.class_eval do
        private

        def send_notification_with_other(*args)
          @other_calls = (@other_calls || 0) + 1
          send_notification_without_other(*args)
        end
        alias_method :send_notification_without_other, :send_notification
        alias_method :send_notification, :send_notification_with_other

        public

        attr_reader :other_calls
      end
    end

    it 'runs the chain once and still suppresses' do
      issue = Issue.new
      expect { issue.save }.not_to raise_error
      expect([issue.other_calls, issue.notif_calls]).to eq([1, 1])

      Thread.current[:redmine_extended_api_suppress_notifications] = true
      quiet = Issue.new
      expect { quiet.save }.not_to raise_error
      expect([quiet.other_calls, quiet.notif_calls]).to eq([1, 0])
    end
  end
end

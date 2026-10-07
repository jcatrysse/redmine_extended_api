# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/notification_suppression_patch'

RSpec.describe RedmineExtendedApi::Patches::NotificationSuppressionPatch do
  let(:issue_class) do
    Class.new do
      def send_notification(*)
        @calls ||= 0
        @calls += 1
      end

      def notif_calls
        @calls || 0
      end
    end
  end

  let(:journal_class) do
    Class.new do
      def send_notification(*)
        @calls ||= 0
        @calls += 1
      end

      def notif_calls
        @calls || 0
      end
    end
  end

  before do
    # Simuleer echte Redmine classes
    stub_const('Issue', issue_class)
    stub_const('Journal', journal_class)

    # Prepend de patch zoals init.rb doet
    Issue.prepend(described_class)
    Journal.prepend(described_class)
  end

  after do
    Thread.current[:redmine_extended_api_suppress_notifications] = nil
  end

  it 'does not suppress notifications when the thread flag is not set (Issue)' do
    issue = Issue.new
    issue.send(:send_notification)
    expect(issue.notif_calls).to eq(1)
  end

  it 'suppresses notifications when the thread flag is set (Issue)' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    issue = Issue.new
    issue.send(:send_notification)
    expect(issue.notif_calls).to eq(0)
  end

  context 'when send_notification is private' do
    let(:issue_class) do
      Class.new do
        private

        def send_notification(*)
          @calls ||= 0
          @calls += 1
        end

        public

        def notif_calls
          @calls || 0
        end
      end
    end

    it 'still suppresses notifications' do
      Thread.current[:redmine_extended_api_suppress_notifications] = true

      issue = Issue.new
      issue.send(:send_notification)

      expect(issue.notif_calls).to eq(0)
    end
  end

  it 'suppresses notifications when the thread flag is set (Journal)' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    journal = Journal.new
    journal.send(:send_notification)
    expect(journal.notif_calls).to eq(0)
  end

  it 'does not leak suppression between examples' do
    issue = Issue.new
    issue.send(:send_notification)
    expect(issue.notif_calls).to eq(1)
  end

  it 'keeps send_notification private, as it is in Redmine' do
    expect(Issue.new.respond_to?(:send_notification)).to be(false)
    expect(Issue.private_method_defined?(:send_notification)).to be(true)
  end

  # Another plugin (redmine_stealth) prepends send_notification as well. With the former
  # alias_method chain, a module prepended before ours made send_notification call itself.
  context 'with another plugin that prepends send_notification' do
    let(:other_plugin) do
      Module.new do
        def send_notification(*)
          @other_calls = (@other_calls || 0) + 1
          super
        end
      end
    end

    let(:issue_class) do
      Class.new do
        attr_reader :other_calls

        def notif_calls
          @calls || 0
        end

        private

        def send_notification(*)
          @calls = (@calls || 0) + 1
        end
      end
    end

    it 'runs the other plugin and the original once when the other plugin came first' do
      klass = Class.new(issue_class)
      klass.prepend(other_plugin)
      klass.prepend(described_class)

      issue = klass.new
      expect { issue.send(:send_notification) }.not_to raise_error
      expect([issue.other_calls, issue.notif_calls]).to eq([1, 1])
    end

    it 'still suppresses when the other plugin came first' do
      klass = Class.new(issue_class)
      klass.prepend(other_plugin)
      klass.prepend(described_class)
      Thread.current[:redmine_extended_api_suppress_notifications] = true

      issue = klass.new
      issue.send(:send_notification)
      expect([issue.other_calls, issue.notif_calls]).to eq([nil, 0])
    end
  end
end

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

    # Include de patch zoals je init.rb zou doen
    Issue.send(:include, described_class) unless Issue.included_modules.include?(described_class)
    Journal.send(:include, described_class) unless Journal.included_modules.include?(described_class)
  end

  after do
    Thread.current[:redmine_extended_api_suppress_notifications] = nil
  end

  it 'does not suppress notifications when the thread flag is not set (Issue)' do
    issue = Issue.new
    issue.send_notification
    expect(issue.notif_calls).to eq(1)
  end

  it 'suppresses notifications when the thread flag is set (Issue)' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    issue = Issue.new
    issue.send_notification
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
    journal.send_notification
    expect(journal.notif_calls).to eq(0)
  end

  it 'does not leak suppression between examples' do
    issue = Issue.new
    issue.send_notification
    expect(issue.notif_calls).to eq(1)
  end
end

# frozen_string_literal: true

require_relative 'spec_helper'
require 'active_support'
require 'active_support/time'
require 'active_support/core_ext/object/blank'
require_relative '../lib/redmine_extended_api/patches/issue_patch'

RSpec.describe RedmineExtendedApi::Patches::IssuePatch do
  let(:journal_class) do
    Class.new do
      attr_reader :attributes
      attr_accessor :notify

      def initialize
        @attributes = {}
      end

      def assign_attributes(attrs)
        @attributes.merge!(attrs)
      end
    end
  end

  let(:issue_class) do
    Class.new do
      attr_reader :assigned_attributes, :safe_attributes_payload, :init_journal_args, :current_journal
      attr_accessor :notify

      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.after_save(_callback = nil); end

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

      def self.update_all_calls
        @update_all_calls ||= []
      end

      def self.where(conditions)
        calls = update_all_calls
        Object.new.tap do |relation|
          relation.define_singleton_method(:update_all) { |cols| calls << [conditions, cols] }
        end
      end

      def id
        42
      end

      def clear_attribute_changes(names)
        @cleared_attribute_changes = names
      end

      attr_reader :cleared_attribute_changes
    end.tap { |klass| klass.include described_class }
  end

  let(:issue) { issue_class.new }
  let(:admin_user) { double('User', admin?: true) }
  let(:non_admin_user) { double('User', admin?: false) }

  before do
    stub_const('User', Class.new do
      class << self
        attr_accessor :current
      end
    end)

    stub_const('Journal', journal_class)

    Time.zone = 'UTC'
  end

  after do
    Thread.current[:redmine_extended_api_issue_overrides] = nil
    Thread.current[:redmine_extended_api_journal_overrides] = nil
    Thread.current[:redmine_extended_api_suppress_notifications] = nil
  end

  it 'applies issue override attributes for admins (pre-save via safe_attributes=)' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = {
      author_id: 3,
      created_on: '2020-01-01',
      updated_on: '2020-01-02',
      closed_on: '2020-01-03',
      other: 'ignored'
    }

    issue.safe_attributes=({ subject: 'New' })

    expect(issue.assigned_attributes).to eq(
                                           author_id: 3,
                                           created_on: '2020-01-01',
                                           updated_on: '2020-01-02',
                                           closed_on: '2020-01-03'
                                         )
  end

  it 'ignores issue overrides for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = { author_id: 3 }

    issue.safe_attributes=({ subject: 'New' })

    expect(issue.assigned_attributes).to be_nil
  end

  it 'sets notify=false for issues when suppression flag is set for any user' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    issue.safe_attributes=({ subject: 'New' })

    expect(issue.notify).to be(false)
  end

  it 'applies journal overrides on init_journal for admins (pre-save on journal instance)' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = {
      user_id: 9,
      updated_by_id: 4,
      created_on: '2020-02-01',
      updated_on: '2020-02-02'
    }

    issue.init_journal(admin_user, 'note')

    expect(issue.init_journal_args).to eq([admin_user, 'note'])
    expect(issue.current_journal.attributes).to eq(
                                                  user_id: 9,
                                                  updated_by_id: 4,
                                                  created_on: '2020-02-01',
                                                  updated_on: '2020-02-02'
                                                )
  end

  it 'does not apply journal overrides on init_journal for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = { user_id: 9, updated_on: '2020-02-02' }

    issue.init_journal(non_admin_user, 'note')

    expect(issue.current_journal.attributes).to eq({})
  end

  it 'sets notify=false for journals when suppression flag is set for any user' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    issue.init_journal(non_admin_user, 'note')

    expect(issue.current_journal.notify).to be(false)
  end

  it 'forces issue timestamps and author after save with update_all on the id only, for admins' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = {
      created_on: '2020-01-01 10:00:00',
      updated_on: '2020-01-02 11:00:00',
      closed_on:  '2020-01-03 12:00:00',
      author_id: 3
    }

    issue.send(:apply_extended_api_issue_overrides_after_save)

    # update_all on the id alone: update_columns would add the in-memory lock_version to the
    # WHERE (Rails 7.1+), which is stale on create and made the update hit no row.
    expect(issue_class.update_all_calls.size).to eq(1)
    conditions, cols = issue_class.update_all_calls.first
    expect(conditions).to eq(id: 42)

    expect(cols[:author_id]).to eq(3)
    expect(cols[:created_on]).to be_a(Time)
    expect(cols[:updated_on]).to be_a(Time)
    expect(cols[:closed_on]).to be_a(Time)
    expect(issue.assigned_attributes).to eq(cols)
    expect(issue.cleared_attribute_changes).to match_array(%i[author_id created_on updated_on closed_on])
  end

  it 'does not force issue timestamps after save for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = {
      created_on: '2020-01-01 10:00:00'
    }

    issue.send(:apply_extended_api_issue_overrides_after_save)

    expect(issue_class.update_all_calls).to be_empty
  end
end

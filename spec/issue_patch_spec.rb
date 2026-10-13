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

      def self.before_validation(_callback = nil); end

      def persisted?
        true
      end

      # the save that inserted it (a create)
      def saved_change_to_id?
        true
      end

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
    end.tap { |klass| klass.prepend described_class }
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
    Thread.current[:redmine_extended_api_issue_target_id] = nil
  end

  # the before_validation callback, on the issue the request updates
  def validate_issue(record)
    Thread.current[:redmine_extended_api_issue_target_id] = '42'
    record.send(:apply_extended_api_issue_overrides_before_validation)
  end

  it 'applies issue override attributes for admins (pre-save, before validation)' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = {
      author_id: 3,
      created_on: '2020-01-01',
      updated_on: '2020-01-02',
      closed_on: '2020-01-03',
      other: 'ignored'
    }

    validate_issue(issue)

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

    validate_issue(issue)

    expect(issue.assigned_attributes).to be_nil
  end

  it 'sets notify=false for issues when suppression flag is set for any user' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    validate_issue(issue)

    expect(issue.notify).to be(false)
  end

  # The journal overrides and notify=false are set on the journal itself (JournalPatch,
  # NotificationSuppressionPatch, see their specs); init_journal stays core's.
  it 'leaves init_journal to core' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = { user_id: 9 }

    issue.init_journal(admin_user, 'note')

    expect(described_class.instance_methods).not_to include(:init_journal)
    expect(issue.init_journal_args).to eq([admin_user, 'note'])
    expect(issue.current_journal.attributes).to eq({})
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

  # Other plugins (redmine_itil_priority) patch Issue#safe_attributes= too. With the former
  # alias_method chain, a module prepended before ours made safe_attributes= call itself.
  it 'works next to another plugin that prepends safe_attributes= and init_journal first' do
    other_plugin = Module.new do
      def safe_attributes=(attrs, user = nil)
        (@other_calls ||= []) << :safe_attributes
        super
      end

      def init_journal(user, notes = '')
        (@other_calls ||= []) << :init_journal
        super
      end

      def other_calls
        @other_calls
      end
    end
    klass = Class.new(issue_class.superclass == Object ? Object : issue_class.superclass)
    base = Class.new do
      attr_reader :assigned_attributes, :safe_attributes_payload, :current_journal

      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.after_save(_callback = nil); end

      def self.before_validation(_callback = nil); end

      def persisted?
        true
      end

      def id
        42
      end

      def safe_attributes=(attrs, _user = nil)
        @safe_attributes_payload = attrs
      end

      def init_journal(_user, _notes = '')
        @current_journal = Journal.new
      end

      def assign_attributes(attrs)
        (@assigned_attributes ||= {}).merge!(attrs)
      end
    end
    base.prepend(other_plugin)
    base.prepend(described_class)
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = { author_id: 3 }
    Thread.current[:redmine_extended_api_journal_overrides] = { user_id: 9 }

    issue = base.new
    expect { issue.safe_attributes = { subject: 'New' } }.not_to raise_error
    expect { issue.init_journal(admin_user, 'note') }.not_to raise_error
    validate_issue(issue)

    expect(issue.safe_attributes_payload).to eq(subject: 'New')
    expect(issue.assigned_attributes).to eq(author_id: 3)
    expect(issue.current_journal.attributes).to eq({}) # JournalPatch sets them, before validation
    expect(issue.other_calls).to eq(%i[safe_attributes init_journal])
    expect(klass).to be_a(Class)
  end

  # redmine_tags (master, Redmine 5.1) loads after this plugin and builds an alias_method
  # chain on safe_attributes=. When this patch overrode safe_attributes= with prepend, the
  # chain called itself: SystemStackError on every POST /issues.json.
  it 'works next to a plugin that alias_method chains safe_attributes= after the prepend' do
    base = Class.new do
      attr_reader :assigned_attributes, :safe_attributes_payload, :tag_list

      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.after_save(_callback = nil); end

      def self.before_validation(_callback = nil); end

      def persisted?
        true
      end

      def id
        42
      end

      def safe_attributes=(attrs, _user = nil)
        @safe_attributes_payload = attrs
      end

      def assign_attributes(attrs)
        (@assigned_attributes ||= {}).merge!(attrs)
      end
    end
    base.prepend(described_class)
    base.class_eval do
      def safe_attributes_with_safe_tags=(attrs, user = nil)
        send(:safe_attributes_without_safe_tags=, attrs, user)
        @tag_list = attrs[:tag_list]
      end
      alias_method :safe_attributes_without_safe_tags=, :safe_attributes=
      alias_method :safe_attributes=, :safe_attributes_with_safe_tags=
    end
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = { author_id: 3 }

    issue = base.new
    expect { issue.safe_attributes = { subject: 'New', tag_list: ['a'] } }.not_to raise_error
    validate_issue(issue)

    expect(issue.safe_attributes_payload).to eq(subject: 'New', tag_list: ['a'])
    expect(issue.tag_list).to eq(['a'])
    expect(issue.assigned_attributes).to eq(author_id: 3)
  end

  it 'does not force the overrides after save on an issue the request did not create or name' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = { author_id: 3, created_on: '2020-01-01 00:00:00' }
    issue.define_singleton_method(:saved_change_to_id?) { false }

    issue.send(:apply_extended_api_issue_overrides_after_save)
    Thread.current[:redmine_extended_api_issue_target_id] = '7'
    issue.send(:apply_extended_api_issue_overrides_after_save)

    expect(issue_class.update_all_calls).to be_empty
  end

  # The same for init_journal: when this patch prepended it, a later alias_method chain recursed.
  it 'works next to a plugin that alias_method chains init_journal after the prepend' do
    base = Class.new do
      attr_reader :current_journal

      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.after_save(_callback = nil); end

      def self.before_validation(_callback = nil); end

      def init_journal(_user, notes = '')
        @current_journal ||= Journal.new.tap { |j| j.assign_attributes(notes: notes) }
      end
    end
    base.prepend(described_class)
    base.class_eval do
      def init_journal_with_other(user, notes = '')
        (@other_calls ||= []) << :init_journal
        init_journal_without_other(user, notes)
      end
      alias_method :init_journal_without_other, :init_journal
      alias_method :init_journal, :init_journal_with_other
      attr_reader :other_calls
    end
    User.current = admin_user

    issue = base.new
    expect { issue.init_journal(admin_user, 'note') }.not_to raise_error
    expect(issue.other_calls).to eq(%i[init_journal])
    expect(issue.current_journal.attributes).to eq(notes: 'note')
  end

  it 'leaves other issues saved in the same request alone' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_issue_overrides] = { author_id: 3 }
    Thread.current[:redmine_extended_api_issue_target_id] = '7'

    issue.send(:apply_extended_api_issue_overrides_before_validation)

    expect(issue.assigned_attributes).to be_nil
  end
end

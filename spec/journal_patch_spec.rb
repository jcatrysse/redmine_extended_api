# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/journal_patch'

RSpec.describe RedmineExtendedApi::Patches::JournalPatch do
  let(:journal_class) do
    Class.new do
      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.after_save(_callback = nil); end

      def self.before_validation(_callback = nil); end

      def self.before_save(_callback = nil, **); end

      attr_writer :journalized_id, :new_record

      # a new journal on issue 42, saved by this request
      def journalized_type
        'Issue'
      end

      def journalized_id
        @journalized_id || 42
      end

      def new_record?
        @new_record != false
      end

      def saved_change_to_id?
        true
      end

      def update_columns(cols)
        @update_columns_calls ||= []
        @update_columns_calls << cols
      end

      def update_columns_calls
        @update_columns_calls ||= []
      end

      def assign_attributes(cols)
        (@assigned_attributes ||= {}).merge!(cols)
      end

      attr_reader :assigned_attributes
    end.tap { |klass| klass.include described_class }
  end

  let(:journal) { journal_class.new }
  let(:admin_user) { double('User', admin?: true) }
  let(:non_admin_user) { double('User', admin?: false) }

  before do
    stub_const('User', Class.new do
      class << self
        attr_accessor :current
      end
    end)

    Time.zone = 'UTC'
  end

  after do
    Thread.current[:redmine_extended_api_journal_overrides] = nil
    Thread.current[:redmine_extended_api_issue_target_id] = nil
    Thread.current[:redmine_extended_api_skip_journal] = nil
  end

  # the request updates issue 42
  before { Thread.current[:redmine_extended_api_issue_target_id] = '42' }

  # moved here from issue_patch_spec: the overrides were set in Issue#init_journal before
  it 'applies journal overrides before validation for admins (pre-save on the new journal)' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = {
      user_id: 9, updated_by_id: 4, created_on: '2020-02-01', updated_on: '2020-02-02', other: 'x'
    }

    journal.send(:apply_extended_api_journal_overrides_before_validation)

    expect(journal.assigned_attributes).to eq(user_id: 9, updated_by_id: 4, created_on: '2020-02-01', updated_on: '2020-02-02')
  end

  it 'does not apply journal overrides before validation for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = { user_id: 9, updated_on: '2020-02-02' }

    journal.send(:apply_extended_api_journal_overrides_before_validation)

    expect(journal.assigned_attributes).to be_nil
  end

  # A request that closes duplicates or adds relations writes journals on other issues too;
  # they kept the overrides of the imported journal before.
  it 'leaves journals on other issues, and existing journals, alone' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = { user_id: 9, created_on: '2020-02-01 10:00:00' }

    other = journal_class.new.tap { |j| j.journalized_id = 7 }
    other.send(:apply_extended_api_journal_overrides_before_validation)
    other.send(:apply_extended_api_journal_overrides_after_save)
    existing = journal_class.new.tap { |j| j.new_record = false }
    existing.send(:apply_extended_api_journal_overrides_before_validation)

    expect(other.assigned_attributes).to be_nil
    expect(other.update_columns_calls).to be_empty
    expect(existing.assigned_attributes).to be_nil
  end

  it 'forces journal overrides after save using update_columns for admins' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = {
      user_id: 9,
      updated_by_id: 4,
      created_on: '2020-02-01 10:00:00',
      updated_on: '2020-02-01 10:05:00'
    }

    journal.send(:apply_extended_api_journal_overrides_after_save)

    expect(journal.update_columns_calls.size).to eq(1)
    cols = journal.update_columns_calls.first

    expect(cols[:user_id]).to eq(9)
    expect(cols[:updated_by_id]).to eq(4)
    expect(cols[:created_on]).to be_a(Time)
    expect(cols[:updated_on]).to be_a(Time)
  end

  it 'does not force journal overrides for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_journal_overrides] = { user_id: 9, created_on: '2020-02-01 10:00:00' }

    journal.send(:apply_extended_api_journal_overrides_after_save)

    expect(journal.update_columns_calls).to be_empty
  end

  # skip_journal: Issue#create_journal, create_parent_issue_journal and the relation journals all
  # end in Journal#save, which stops here
  it 'stops a new journal from being saved while skip_journal is set' do
    Thread.current[:redmine_extended_api_skip_journal] = true

    expect(catch(:abort) { journal.send(:skip_extended_api_journal); :saved }).to be_nil
  end

  it 'lets journals be saved without skip_journal, and existing ones with it' do
    expect(catch(:abort) { journal.send(:skip_extended_api_journal); :saved }).to eq(:saved)

    Thread.current[:redmine_extended_api_skip_journal] = true
    existing = journal_class.new.tap { |j| j.new_record = false }
    expect(catch(:abort) { existing.send(:skip_extended_api_journal); :saved }).to eq(:saved)
  end

  it 'puts updated_on and updated_by back after a journal edit with skip_journal' do
    edited = journal_class.new
    old_time = Time.utc(2019, 4, 5)
    edited.define_singleton_method(:saved_change_to_id?) { false }
    edited.define_singleton_method(:saved_change_to_updated_on?) { true }
    edited.define_singleton_method(:saved_change_to_updated_by_id?) { true }
    edited.define_singleton_method(:updated_on_before_last_save) { old_time }
    edited.define_singleton_method(:updated_by_id_before_last_save) { 2 }

    edited.send(:keep_extended_api_journal_edit_metadata)
    expect(edited.update_columns_calls).to be_empty

    Thread.current[:redmine_extended_api_skip_journal] = true
    edited.send(:keep_extended_api_journal_edit_metadata)
    expect(edited.update_columns_calls).to eq([{updated_on: old_time, updated_by_id: 2}])
  end
end

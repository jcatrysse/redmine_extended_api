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

      def update_columns(cols)
        @update_columns_calls ||= []
        @update_columns_calls << cols
      end

      def update_columns_calls
        @update_columns_calls ||= []
      end

      def assign_attributes(_cols); end
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
end

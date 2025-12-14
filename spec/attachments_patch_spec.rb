# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/api_helpers'
require_relative '../lib/redmine_extended_api/patches/attachments_controller_patch'
require_relative '../lib/redmine_extended_api/patches/attachment_patch'

RSpec.describe RedmineExtendedApi::Patches::AttachmentsControllerPatch do
  let(:controller_class) do
    Class.new do
      include RedmineExtendedApi::Patches::ApiHelpers

      attr_accessor :params, :thread_snapshot, :extended_enabled, :request

      def initialize
        @extended_enabled = true
      end

      def extended_api_request?
        extended_enabled
      end

      def api_request?
        true
      end

      def upload
        @thread_snapshot = Thread.current[:redmine_extended_api_attachment_overrides]
        :base_upload
      end
    end.tap { |klass| klass.prepend described_class }
  end

  let(:controller) { controller_class.new }

  before do
    controller.request = double('Request', env: {
      'redmine_extended_api.original_script_name' => '',
      'redmine_extended_api.original_path_info' => '/extended_api/uploads.json'
    })
  end

  after do
    Thread.current[:redmine_extended_api_attachment_overrides] = nil
  end

  it 'wraps upload with override capture' do
    controller.params = { attachment: { author_id: 5, created_on: '2020-01-01' } }
    allow(controller).to receive(:allow_extended_api_attachment_overrides?).and_return(true)

    expect(controller.upload).to eq(:base_upload)
    expect(controller.thread_snapshot).to eq(author_id: 5, created_on: '2020-01-01')
    expect(Thread.current[:redmine_extended_api_attachment_overrides]).to be_nil
  end

  it 'falls back to the base action when the request is not extended' do
    controller.params = { attachment: { author_id: 5 } }
    allow(controller).to receive(:extended_api_request?).and_return(false)

    expect(controller.upload).to eq(:base_upload)
    expect(controller.thread_snapshot).to be_nil
  end

  it 'stores nothing when no override keys are present' do
    controller.params = { attachment: { description: 'Keep defaults' } }

    expect(controller.upload).to eq(:base_upload)
    expect(controller.thread_snapshot).to eq({})
  end

  it 'ignores override capture when attachment overrides are not allowed' do
    controller.params = { attachment: { author_id: 5 } }
    allow(controller).to receive(:allow_extended_api_attachment_overrides?).and_return(false)

    expect(controller.upload).to eq(:base_upload)
    expect(controller.thread_snapshot).to eq({})
    expect(Thread.current[:redmine_extended_api_attachment_overrides]).to be_nil
  end
end

RSpec.describe RedmineExtendedApi::Patches::AttachmentPatch do
  let(:attachment_class) do
    Class.new do
      attr_reader :assigned_attributes, :safe_attributes_payload

      def self.class_attribute(name, **)
        singleton_class.class_eval { attr_accessor name }
      end

      def self.before_validation(callback)
        @callbacks ||= []
        @callbacks << callback
      end

      def self.after_save(callback)
        @after_save_callbacks ||= []
        @after_save_callbacks << callback
      end

      def self.run_before_validation_callbacks(instance)
        Array(@callbacks).each { |callback| instance.send(callback) }
      end

      def self.run_after_save_callbacks(instance)
        Array(@after_save_callbacks).each { |callback| instance.send(callback) }
      end

      def assign_attributes(attrs)
        @assigned_attributes ||= {}
        @assigned_attributes.merge!(attrs)
      end

      def safe_attributes=(attrs, user = nil)
        @safe_attributes_payload = attrs
      end

      def update_columns(cols)
        @update_columns_calls ||= []
        @update_columns_calls << cols
      end

      def update_columns_calls
        @update_columns_calls ||= []
      end
    end.tap { |klass| klass.include described_class }
  end

  let(:attachment) { attachment_class.new }
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
    Thread.current[:redmine_extended_api_attachment_overrides] = nil
    Thread.current[:redmine_extended_api_applying_attachment_overrides] = nil
  end

  it 'applies override attributes for admins after safe assignment' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_attachment_overrides] = { author_id: 3, created_on: '2020-01-01', ignored: 'x' }

    attachment.safe_attributes=({ description: 'New attachment' })

    expect(attachment.assigned_attributes).to eq(author_id: 3, created_on: '2020-01-01')
  end

  it 'ignores overrides for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_attachment_overrides] = { author_id: 3 }

    attachment.safe_attributes=({ description: 'New attachment' })

    expect(attachment.assigned_attributes).to be_nil
  end

  it 'applies overrides during validation callbacks when safe attributes are not used' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_attachment_overrides] = { created_on: '2020-03-03' }

    attachment_class.run_before_validation_callbacks(attachment)

    expect(attachment.assigned_attributes).to eq(created_on: '2020-03-03')
  end

  it 'forces author_id and created_on after save using update_columns for admins' do
    User.current = admin_user
    Thread.current[:redmine_extended_api_attachment_overrides] = {
      author_id: 9,
      created_on: '2020-03-03 12:00:00'
    }

    attachment_class.run_after_save_callbacks(attachment)

    expect(attachment.update_columns_calls.size).to eq(1)
    cols = attachment.update_columns_calls.first
    expect(cols[:author_id]).to eq(9)
    expect(cols[:created_on]).to be_a(Time)
  end

  it 'does not force after save for non-admin users' do
    User.current = non_admin_user
    Thread.current[:redmine_extended_api_attachment_overrides] = {
      created_on: '2020-03-03 12:00:00'
    }

    attachment_class.run_after_save_callbacks(attachment)

    expect(attachment.update_columns_calls).to be_empty
  end
end

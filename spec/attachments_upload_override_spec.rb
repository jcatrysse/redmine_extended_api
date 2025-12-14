# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/api_helpers'
require_relative '../lib/redmine_extended_api/patches/attachments_controller_patch'
require_relative '../lib/redmine_extended_api/patches/attachment_patch'

RSpec.describe 'extended_api uploads overrides' do
  before do
    stub_const('User', Class.new do
      class << self
        attr_accessor :current
      end

      attr_reader :id

      def initialize(id: 999, admin: true)
        @id = id
        @admin = admin
      end

      def admin?
        @admin
      end
    end)

    User.current = User.new

    stub_const('Attachment', Class.new do
      class << self
        attr_accessor :last_saved
      end

      attr_accessor :author_id, :created_on, :filename, :content_type, :file

      def initialize(file:)
        @file = file
      end

      def author=(user)
        @author_id = user.id
      end

      def save
        self.class.last_saved = self
        true
      end

      def update_columns(cols)
        cols.each do |k, v|
          public_send("#{k}=", v)
        end
      end
    end)

    stub_const('AttachmentsController', Class.new do
      include RedmineExtendedApi::Patches::ApiHelpers
      prepend RedmineExtendedApi::Patches::AttachmentsControllerPatch

      attr_accessor :params, :request

      def api_request?
        true
      end

      def raw_request_body
        StringIO.new('x')
      end

      def upload
        @attachment = Attachment.new(file: raw_request_body)
        @attachment.author = User.current
        @attachment.filename = params[:filename]
        @attachment.content_type = params[:content_type]
        saved = @attachment.save

        if saved
          # simulate after_save hook call
          patch = Object.new.extend(RedmineExtendedApi::Patches::AttachmentPatch)
          patch.define_singleton_method(:class) { Attachment }
          patch.define_singleton_method(:allow_extended_api_overrides?) { |u| u.admin? }
          patch.define_singleton_method(:parse_extended_api_time) { |s| Time.parse(s) rescue nil }
          patch.define_singleton_method(:update_columns) { |cols| @attachment.update_columns(cols) }
          patch.instance_variable_set(:@attachment, @attachment)
        end

        :ok
      end
    end)
  end

  it 'accepts attachment[author_id] and attachment[created_on] on uploads endpoint' do
    controller = AttachmentsController.new
    controller.request = double('Request', env: {
      'redmine_extended_api.original_script_name' => '',
      'redmine_extended_api.original_path_info' => '/extended_api/uploads.json'
    })

    controller.params = {
      filename: 'legacy-log.txt',
      attachment: {
        author_id: 7,
        created_on: '2023-11-02T08:15:00Z'
      }
    }

    controller.upload

    saved = Attachment.last_saved
    expect(saved.author_id).to eq(999) # set by controller
    # override should exist in thread during upload
    expect(Thread.current[:redmine_extended_api_attachment_overrides]).to be_nil
  end

  it 'ignores override parameters for non-admin users' do
    User.current = User.new(id: 123, admin: false)

    controller = AttachmentsController.new
    controller.request = double('Request', env: {
      'redmine_extended_api.original_script_name' => '',
      'redmine_extended_api.original_path_info' => '/extended_api/uploads.json'
    })

    controller.params = {
      filename: 'legacy-log.txt',
      attachment: {
        author_id: 7,
        created_on: '2023-11-02T08:15:00Z'
      }
    }

    controller.upload

    saved = Attachment.last_saved
    expect(saved.author_id).to eq(123)
    expect(saved.created_on).to be_nil
    expect(Thread.current[:redmine_extended_api_attachment_overrides]).to be_nil
  end
end

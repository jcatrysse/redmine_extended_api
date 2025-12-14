# frozen_string_literal: true

require 'ostruct'
require 'active_support/core_ext/object/blank'
require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/patches/api_helpers'
require_relative '../lib/redmine_extended_api/patches/roles_controller_patch'
require_relative '../lib/redmine_extended_api/patches/custom_fields_controller_patch'
require_relative '../lib/redmine_extended_api/patches/enumerations_controller_patch'
require_relative '../lib/redmine_extended_api/patches/issue_statuses_controller_patch'
require_relative '../lib/redmine_extended_api/patches/trackers_controller_patch'

unless defined?(ActiveRecord)
  module ActiveRecord
    class RecordNotFound < StandardError; end
  end
end

RSpec.describe 'Controller patches' do
  ErrorsStub = Class.new do
    def add(*)
    end
  end

  ResponseStub = Class.new do
    attr_accessor :headers

    def initialize
      @headers = {}
    end

    def set_header(name, value)
      headers[name] = value
    end
  end

  describe RedmineExtendedApi::Patches::ApiHelpers do
    let(:dummy_class) do
      Class.new do
        include RedmineExtendedApi::Patches::ApiHelpers

        attr_accessor :request

        def initialize
          @response = ResponseStub.new
        end

        def api_request?
          true
        end

        def response
          @response
        end
      end
    end

    let(:instance) { dummy_class.new }

    it 'returns true when the original path is prefixed with /extended_api' do
      request = double('Request', env: {
                           'redmine_extended_api.original_script_name' => '',
                           'redmine_extended_api.original_path_info' => '/extended_api/roles.json'
                         })

      instance.request = request

      expect(instance.send(:extended_api_request?)).to be(true)
    end

    it 'returns true when the original script name contains the /extended_api prefix' do
      request = double('Request', env: {
                           'redmine_extended_api.original_script_name' => '/redmine/extended_api',
                           'redmine_extended_api.original_path_info' => '/roles.json'
                         })

      instance.request = request

      expect(instance.send(:extended_api_request?)).to be(true)
    end

    it 'returns false when the request is not routed through the extended API proxy' do
      request = double('Request', env: {
                           'redmine_extended_api.original_script_name' => '/redmine',
                           'redmine_extended_api.original_path_info' => '/roles.json'
                         })

      instance.request = request

      expect(instance.send(:extended_api_request?)).to be(false)
    end

    it 'returns false when the call is not an API request' do
      allow(instance).to receive(:api_request?).and_return(false)
      request = double('Request', env: {
                           'redmine_extended_api.original_script_name' => '',
                           'redmine_extended_api.original_path_info' => '/extended_api/roles.json'
                         })

      instance.request = request

      expect(instance.send(:extended_api_request?)).to be(false)
    end

    it 'exposes native metadata by default' do
      expect(instance.send(:extended_api_metadata)).to eq(mode: 'native', fallback_to_native: true)
    end

    it 'marks the response as extended when requested' do
      instance.send(:mark_extended_api_response, fallback: false)

      expect(instance.send(:extended_api_metadata)).to eq(mode: 'extended', fallback_to_native: false)
      expect(instance.response.headers['X-Redmine-Extended-API']).to eq('extended')
    end
  end

  def build_controller(patch_module)
    Class.new do
      class << self
        attr_reader :accepted_actions

        def accept_api_auth(*actions)
          @accepted_actions ||= []
          @accepted_actions.concat(actions)
        end

        def helper_methods
          @helper_methods ||= []
        end

        def helper_method(*methods)
          helper_methods.concat(methods)
        end
      end

      attr_accessor :params, :request

      def initialize
        @super_calls = Hash.new(0)
        @render_404_calls = 0
        @response = ResponseStub.new
      end

      def super_calls
        @super_calls
      end

      def render_404_calls
        @render_404_calls
      end

      def api_request?
        false
      end

      def create
        @super_calls[:create] += 1
        :base_create
      end

      def show
        @super_calls[:show] += 1
        :base_show
      end

      def index
        @super_calls[:index] += 1
        :base_index
      end

      def update
        @super_calls[:update] += 1
        :base_update
      end

      def destroy
        @super_calls[:destroy] += 1
        :base_destroy
      end

      def render(*)
      end

      def render_404(*)
        @render_404_calls += 1
        :render_404
      end

      def head(*)
      end

      def response
        @response
      end

      def role_url(*)
        raise 'stubbed'
      end

      def custom_fields_url(*)
        raise 'stubbed'
      end

      def enumerations_url(*)
        raise 'stubbed'
      end

      def issue_statuses_url(*)
        raise 'stubbed'
      end

      def trackers_url(*)
        raise 'stubbed'
      end

      def enumeration_params
        raise 'stubbed'
      end

      def respond_to
        yield OpenStruct.new(api: ->(&block) { block.call })
      end

      def call_hook(*)
      end
    end.tap do |klass|
      klass.prepend patch_module
    end
  end

  describe RedmineExtendedApi::Patches::RolesControllerPatch do
    let(:controller_class) { build_controller(described_class) }

    describe '.prepended' do
      it 'registers API auth actions' do
        expect(controller_class.accepted_actions).to match_array(%i[index show create update destroy])
      end

      it 'exposes the extended API metadata helper to the view layer' do
        expect(controller_class.helper_methods).to include(:extended_api_metadata)
      end
    end

    describe '#create' do
      let(:controller) { controller_class.new }
      let(:request_format) { double(symbol: :json) }
      let(:request) { double('Request', post?: true, format: request_format) }
      let(:role) { double('Role', errors: ErrorsStub.new) }
      let(:save_result) { true }

      before do
        controller.request = request
        controller.params = { role: { name: 'Dev' }, copy_workflow_from: '5' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)

        stub_const('Role', Class.new)
        allow(Role).to receive(:new).and_return(role)

        allow(role).to receive(:safe_attributes=)
        allow(role).to receive(:save).and_return(save_result)
        allow(role).to receive(:copy_workflow_rules)

        allow(controller).to receive(:role_url).with(role, format: :json).and_return('/roles/1.json')
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)
      end

      it 'renders the role and copies workflow rules when saving succeeds' do
        expect(controller).to receive(:copy_workflow_from_role).with(role, '5')
        expect(controller).to receive(:render_extended_api).with(
          'roles/show',
          status: :created,
          location: '/roles/1.json'
        )

        controller.create

        expect(controller.super_calls[:create]).to eq(0)
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).not_to receive(:copy_workflow_from_role)
          expect(controller).to receive(:render_api_validation_errors).with(role)

          controller.create
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'falls back to the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end

      context 'when the request does not use the extended API prefix' do
        before do
          allow(controller).to receive(:extended_api_request?).and_return(false)
        end

        it 'falls back to the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end
    end

    describe '#update' do
      let(:controller) { controller_class.new }
      let(:role_record) { double('Role', errors: ErrorsStub.new) }
      let(:save_result) { true }

      before do
        controller.params = { role: { name: 'Dev' } }
        controller.instance_variable_set(:@role, role_record)
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(role_record).to receive(:safe_attributes=)
        allow(role_record).to receive(:save).and_return(save_result)
      end

      it 'updates the role attributes when saving succeeds' do
        expect(role_record).to receive(:safe_attributes=).with({ name: 'Dev' })
        expect(controller).to receive(:render_extended_api).with('roles/show')

        controller.update

        expect(controller.super_calls[:update]).to eq(0)
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(role_record)

          controller.update
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'delegates to the original action' do
          expect(controller.update).to eq(:base_update)
          expect(controller.super_calls[:update]).to eq(1)
        end
      end
    end

    describe '#destroy' do
      let(:controller) { controller_class.new }
      let(:role_record) { double('Role') }

      before do
        controller.instance_variable_set(:@role, role_record)
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
      end

      it 'destroys the role when allowed' do
        expect(controller).to receive(:destroy_role).with(role_record).and_return(true)
        expect(controller).to receive(:head).with(:no_content)

        controller.destroy
      end

      it 'renders an error when the role cannot be removed' do
        expect(controller).to receive(:destroy_role).with(role_record).and_return(false)
        expect(controller).to receive(:render_api_error_message).with(I18n.t(:error_can_not_remove_role))

        controller.destroy
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.destroy).to eq(:base_destroy)
          expect(controller.super_calls[:destroy]).to eq(1)
        end
      end
    end
  end

  describe RedmineExtendedApi::Patches::CustomFieldsControllerPatch do
    let(:controller_class) { build_controller(described_class) }

    describe '.prepended' do
      it 'registers API auth actions' do
        expect(controller_class.accepted_actions).to match_array(%i[index show create update destroy])
      end

      it 'exposes the extended API metadata helper to the view layer' do
        expect(controller_class.helper_methods).to include(:extended_api_metadata)
      end
    end

    describe '#show' do
      let(:controller) { controller_class.new }
      let(:custom_field) { double('CustomField') }

      before do
        controller.params = { id: '7' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_not_found)

        custom_field_class = Class.new do
          def self.find(_id)
            raise 'stubbed'
          end
        end

        stub_const('CustomField', custom_field_class)
        allow(CustomField).to receive(:find).with('7').and_return(custom_field)
      end

      it 'finds the custom field and renders it' do
        expect(controller).to receive(:render_extended_api).with('custom_fields/show')

        controller.show

        expect(controller.super_calls[:show]).to eq(0)
      end

      context 'when the custom field cannot be found' do
        before do
          allow(CustomField).to receive(:find).and_raise(ActiveRecord::RecordNotFound, 'missing')
        end

        it 'renders a not found API response' do
          expect(controller).not_to receive(:render_extended_api)
          expect(controller).to receive(:render_api_not_found)

          controller.show
        end
      end

      context 'when the base controller does not implement #show' do
        let(:controller_without_show_class) do
          Class.new do
            class << self
              attr_reader :accepted_actions

              def accept_api_auth(*actions)
                @accepted_actions ||= []
                @accepted_actions.concat(actions)
              end
            end

            attr_accessor :params

            def initialize
              @render_404_calls = 0
            end

            def api_request?
              false
            end

            def render_404(*)
              @render_404_calls += 1
            end

            def render_404_calls
              @render_404_calls
            end

            def respond_to
              yield OpenStruct.new(api: ->(&block) { block.call })
            end
          end.tap do |klass|
            klass.prepend RedmineExtendedApi::Patches::CustomFieldsControllerPatch
          end
        end

        it 'renders a 404 when the request does not use the extended API prefix' do
          controller = controller_without_show_class.new
          controller.params = { id: '7' }
          allow(controller).to receive(:extended_api_request?).and_return(false)

          expect { controller.show }.not_to raise_error
          expect(controller.render_404_calls).to eq(1)
        end
      end
    end

    describe '#create' do
      let(:controller) { controller_class.new }
      let(:custom_field) { double('CustomField', errors: ErrorsStub.new) }
      let(:request_format) { double(symbol: :json) }
      let(:request) { double('Request', format: request_format) }
      let(:save_result) { true }
      let(:policy) { instance_double('AttributePolicy', assignable_attributes: [:name]) }

      before do
        controller.instance_variable_set(:@custom_field, custom_field)
        controller.params = { custom_field: { name: 'Field' } }
        controller.request = request
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:custom_fields_url).with(format: :json).and_return('/custom_fields.json')
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)
        allow(controller).to receive(:attribute_policy_for).with(custom_field).and_return(policy)
        allow(custom_field).to receive(:safe_attributes=)
        allow(custom_field).to receive(:field_format).and_return(nil)
        allow(custom_field).to receive(:save).and_return(save_result)
      end

      it 'saves the custom field and renders the template' do
        expect(custom_field).to receive(:safe_attributes=).with({ 'name' => 'Field' })
        expect(controller).to receive(:call_hook).with(
          :controller_custom_fields_new_after_save,
          params: controller.params,
          custom_field: custom_field
        )
        expect(controller).to receive(:render_extended_api).with(
          'custom_fields/show',
          status: :created,
          location: '/custom_fields.json'
        )

        controller.create
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).not_to receive(:call_hook)
          expect(controller).to receive(:render_api_validation_errors).with(custom_field)

          controller.create
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'delegates to the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end

      context 'when the request does not use the extended API prefix' do
        before do
          allow(controller).to receive(:extended_api_request?).and_return(false)
        end

        it 'delegates to the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end
    end

    describe '#update' do
      let(:controller) { controller_class.new }
      let(:custom_field) { double('CustomField', errors: ErrorsStub.new) }
      let(:request_format) { double(symbol: :json) }
      let(:request) { double('Request', format: request_format) }
      let(:save_result) { true }
      let(:policy) { instance_double('AttributePolicy', assignable_attributes: [:name]) }

      before do
        controller.instance_variable_set(:@custom_field, custom_field)
        controller.params = { custom_field: { name: 'Field' } }
        controller.request = request
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:custom_fields_url).with(format: :json).and_return('/custom_fields.json')
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)
        allow(controller).to receive(:attribute_policy_for).with(custom_field).and_return(policy)
        allow(custom_field).to receive(:safe_attributes=)
        allow(custom_field).to receive(:field_format).and_return(nil)
        allow(custom_field).to receive(:save).and_return(save_result)
      end

      it 'updates the custom field and renders the template' do
        expect(custom_field).to receive(:safe_attributes=).with({ 'name' => 'Field' })
        expect(controller).to receive(:call_hook).with(
          :controller_custom_fields_edit_after_save,
          params: controller.params,
          custom_field: custom_field
        )
        expect(controller).to receive(:render_extended_api).with(
          'custom_fields/show',
          status: :ok,
          location: '/custom_fields.json'
        )

        controller.update
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).not_to receive(:call_hook)
          expect(controller).to receive(:render_api_validation_errors).with(custom_field)

          controller.update
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'delegates to the original action' do
          expect(controller.update).to eq(:base_update)
          expect(controller.super_calls[:update]).to eq(1)
        end
      end
    end

    describe '#destroy' do
      let(:controller) { controller_class.new }
      let(:custom_field) { double('CustomField', errors: ErrorsStub.new) }
      let(:destroy_result) { true }

      before do
        controller.instance_variable_set(:@custom_field, custom_field)
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_api_validation_errors)
        allow(controller).to receive(:render_api_error_message)
        allow(custom_field).to receive(:destroy).and_return(destroy_result)
      end

      it 'destroys the custom field when successful' do
        expect(controller).to receive(:head).with(:no_content)

        controller.destroy
      end

      context 'when destroy fails' do
        let(:destroy_result) { false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(custom_field)

          controller.destroy
        end
      end

      context 'when an exception is raised' do
        let(:destroy_result) { true }

        before do
          allow(custom_field).to receive(:destroy).and_raise(StandardError.new('boom'))
        end

        it 'renders an error message' do
          expect(controller).to receive(:render_api_error_message).with('boom')

          controller.destroy
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.destroy).to eq(:base_destroy)
          expect(controller.super_calls[:destroy]).to eq(1)
        end
      end
    end
  end

  describe RedmineExtendedApi::Patches::EnumerationsControllerPatch do
    let(:controller_class) { build_controller(described_class) }

    let(:enumeration_class) do
      Class.new do
        attr_accessor :save_result, :update_result, :destroy_result, :in_use_flag, :destroy_argument
        attr_reader :errors, :name, :objects_count

        def initialize
          @errors = ErrorsStub.new
          @name = 'Example'
          @objects_count = 1
          @save_result = true
          @update_result = true
          @destroy_result = true
          @in_use_flag = false
        end

        def save
          @save_result
        end

        def update(attributes)
          @last_update = attributes
          @update_result
        end

        def last_update
          @last_update
        end

        def in_use?
          @in_use_flag
        end

        def destroy(arg = nil)
          @destroy_argument = arg
          @destroy_result
        end

        class << self
          attr_accessor :find_by_id_result
        end

        def self.find_by_id(_id)
          @find_by_id_result
        end
      end
    end

    describe '.prepended' do
      it 'registers API auth actions' do
        expect(controller_class.accepted_actions).to match_array(%i[index show create update destroy])
      end

      it 'exposes the extended API metadata helper to the view layer' do
        expect(controller_class.helper_methods).to include(:extended_api_metadata)
      end
    end

    describe '#index' do
      let(:controller) { controller_class.new }
      let(:enumeration_record_class) do
        Struct.new(:id, :name, :position, :custom_field_values) do
          def active?
            true
          end

          def is_default?
            false
          end

          def parent_id
            nil
          end

          def project_id
            nil
          end
        end
      end
      let(:record) { enumeration_record_class.new(5, 'High', 1, []) }
      let(:enumeration_base) do
        Class.new do
          class << self
            def subclass_map
              @subclass_map ||= {}
            end

            def register_subclass(identifier, klass)
              subclass_map[identifier.to_s] = klass
            end

            def clear_subclasses
              subclass_map.clear
            end

            def types
              subclass_map.keys
            end

            def descendants
              subclass_map.values
            end

            alias subclasses descendants

            def get_subclass(identifier)
              subclass_map[identifier.to_s]
            end

            def find_by_id(search_id)
              id = search_id.to_s

              subclass_map.values.each do |klass|
                next unless klass.respond_to?(:records) && klass.records

                record = klass.records.find { |item| item.respond_to?(:id) && item.id.to_s == id }
                return record if record
              end

              nil
            end

            def find_by(attributes)
              return find_by_id(attributes[:id]) if attributes.is_a?(Hash) && attributes.key?(:id)

              nil
            end
          end
        end
      end

      let(:enumeration_subclass) do
        Class.new(enumeration_base) do
          class << self
            attr_accessor :records
          end

          def self.model_name
            OpenStruct.new(collection: 'issue_priorities')
          end

          def self.sorted
            records || []
          end

          def self.order(_arg)
            records || []
          end
        end
      end

      before do
        controller.params = {}
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_not_found)

        stub_const('Enumeration', enumeration_base)
        Enumeration.clear_subclasses
      end

      it 'loads all enumeration types when the type parameter is missing' do
        enumeration_subclass.records = [record]
        Enumeration.register_subclass('IssuePriority', enumeration_subclass)

        controller.index

        expect(controller).to have_received(:render_extended_api).with('enumerations/index')
        expect(controller.instance_variable_get(:@enumeration_sets)).to eq([
          {type: 'issue_priorities', enumerations: [record]}
        ])
      end

      it 'renders a single enumeration when the type parameter is numeric and found' do
        controller.params = {type: record.id.to_s}
        enumeration_subclass.records = [record]
        Enumeration.register_subclass('IssuePriority', enumeration_subclass)

        controller.index

        expect(controller).to have_received(:render_extended_api).with('enumerations/show')
        expect(controller).not_to have_received(:render_api_not_found)
        expect(controller.instance_variable_get(:@enumeration)).to eq(record)
      end

      it 'renders not found when the numeric type does not match an enumeration' do
        controller.params = {type: '99'}

        controller.index

        expect(controller).to have_received(:render_api_not_found)
        expect(controller).not_to have_received(:render_extended_api)
      end

      it 'renders not found when the requested type cannot be resolved' do
        controller.params = {type: 'missing'}

        controller.index

        expect(controller).to have_received(:render_api_not_found)
        expect(controller).not_to have_received(:render_extended_api)
      end

      it 'loads enumerations for the provided type' do
        controller.params = {type: 'issue_priorities'}
        enumeration_subclass.records = [record]

        Enumeration.register_subclass('issue_priorities', enumeration_subclass)

        controller.index

        expect(controller).to have_received(:render_extended_api).with('enumerations/index')
        expect(controller.instance_variable_get(:@enumeration_sets)).to eq([
          {type: 'issue_priorities', enumerations: [record]}
        ])
      end

      context 'when the request does not use the extended API prefix' do
        before do
          allow(controller).to receive(:extended_api_request?).and_return(false)
        end

        it 'falls back to the original index action' do
          expect(controller.index).to eq(:base_index)
          expect(controller.super_calls[:index]).to eq(1)
        end
      end
    end

    describe '#show' do
      let(:controller) { controller_class.new }
      let(:enumeration) { double('Enumeration') }

      before do
        controller.params = { id: '12' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_not_found)

        enumeration_class = Class.new do
          def self.find(_id)
            raise 'stubbed'
          end
        end

        stub_const('Enumeration', enumeration_class)
        allow(Enumeration).to receive(:find).with('12').and_return(enumeration)
      end

      it 'finds the enumeration and renders it' do
        expect(controller).to receive(:render_extended_api).with('enumerations/show')

        controller.show

        expect(controller.super_calls[:show]).to eq(0)
      end

      context 'when the enumeration cannot be found' do
        before do
          allow(Enumeration).to receive(:find).and_raise(ActiveRecord::RecordNotFound, 'missing')
        end

        it 'renders a not found API response' do
          expect(controller).not_to receive(:render_extended_api)
          expect(controller).to receive(:render_api_not_found)

          controller.show
        end
      end
    end

    describe '#create' do
      let(:controller) { controller_class.new }
      let(:enumeration) { enumeration_class.new }
      let(:request_format) { double(symbol: :json) }
      let(:request) { double('Request', post?: true, format: request_format) }

      before do
        controller.instance_variable_set(:@enumeration, enumeration)
        controller.params = {}
        controller.request = request
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:enumerations_url).with(format: :json).and_return('/enumerations.json')
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)
      end

      it 'renders the enumeration when saving succeeds' do
        expect(controller).to receive(:render_extended_api).with(
          'enumerations/show',
          status: :created,
          location: '/enumerations.json'
        )

        controller.create
      end

      context 'when saving fails' do
        before { enumeration.save_result = false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(enumeration)

          controller.create
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'uses the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end
    end

    describe '#update' do
      let(:controller) { controller_class.new }
      let(:enumeration) { enumeration_class.new }

      before do
        controller.instance_variable_set(:@enumeration, enumeration)
        controller.params = {}
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)
        allow(controller).to receive(:enumeration_params).and_return(code: 'val')
      end

      it 'updates the enumeration when successful' do
        expect(controller).to receive(:render_extended_api).with('enumerations/show')

        controller.update

        expect(enumeration.last_update).to eq(code: 'val')
      end

      context 'when updating fails' do
        before { enumeration.update_result = false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(enumeration)

          controller.update
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'delegates to the original action' do
          expect(controller.update).to eq(:base_update)
          expect(controller.super_calls[:update]).to eq(1)
        end
      end
    end

    describe '#destroy' do
      let(:controller) { controller_class.new }
      let(:enumeration) { enumeration_class.new }

      before do
        controller.instance_variable_set(:@enumeration, enumeration)
        enumeration_class.find_by_id_result = nil
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_api_validation_errors)
        allow(controller).to receive(:head)
        allow(controller).to receive(:render_api_error_message)
        allow(I18n).to receive(:t).and_return('translation')
      end

      it 'destroys the enumeration when not in use' do
        expect(controller).to receive(:head).with(:no_content)

        controller.destroy
      end

      it 'reassigns before destroying when requested' do
        enumeration.in_use_flag = true
        enumeration_class.find_by_id_result = double('Enumeration')
        controller.params = { reassign_to_id: '12' }

        expect(controller).to receive(:head).with(:no_content)

        controller.destroy

        expect(enumeration.destroy_argument).to eq(enumeration_class.find_by_id_result)
      end

      it 'renders validation errors when the enumeration is in use without reassignment' do
        enumeration.in_use_flag = true
        controller.params = {}

        expect(controller).to receive(:render_api_validation_errors).with(enumeration)

        controller.destroy
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.destroy).to eq(:base_destroy)
          expect(controller.super_calls[:destroy]).to eq(1)
        end
      end
    end
  end

  describe RedmineExtendedApi::Patches::IssueStatusesControllerPatch do
    let(:controller_class) { build_controller(described_class) }
    let(:issue_status_class) do
      Class.new do
        class << self
          def find(_id)
            raise 'stubbed'
          end
        end
      end
    end

    describe '.prepended' do
      it 'registers API auth actions' do
        expect(controller_class.accepted_actions).to match_array(%i[index show create update destroy])
      end

      it 'exposes the extended API metadata helper to the view layer' do
        expect(controller_class.helper_methods).to include(:extended_api_metadata)
      end
    end

    describe '#show' do
      let(:controller) { controller_class.new }
      let(:issue_status) { double('IssueStatus') }

      before do
        controller.params = { id: '9' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_not_found)

        stub_const('IssueStatus', issue_status_class)
        allow(IssueStatus).to receive(:find).with('9').and_return(issue_status)
      end

      it 'finds the issue status and renders it' do
        expect(controller).to receive(:render_extended_api).with('issue_statuses/show')

        controller.show

        expect(controller.super_calls[:show]).to eq(0)
      end

      context 'when the issue status cannot be found' do
        before do
          allow(IssueStatus).to receive(:find).and_raise(ActiveRecord::RecordNotFound, 'missing')
        end

        it 'renders a not found API response' do
          expect(controller).not_to receive(:render_extended_api)
          expect(controller).to receive(:render_api_not_found)

          controller.show
        end
      end
    end

    describe '#create' do
      let(:controller) { controller_class.new }
      let(:issue_status) { double('IssueStatus', errors: ErrorsStub.new) }
      let(:save_result) { true }
      let(:request_format) { double(symbol: :json) }
      let(:request) { double('Request', format: request_format) }

      before do
        controller.params = { issue_status: { name: 'New' } }
        controller.request = request
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:issue_statuses_url).with(format: :json).and_return('/issue_statuses.json')
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)

        stub_const('IssueStatus', issue_status_class)
        allow(IssueStatus).to receive(:new).and_return(issue_status)
        allow(issue_status).to receive(:safe_attributes=)
        allow(issue_status).to receive(:save).and_return(save_result)
      end

      it 'creates the issue status when saving succeeds' do
        expect(issue_status).to receive(:safe_attributes=).with({ name: 'New' })
        expect(controller).to receive(:render_extended_api).with(
          'issue_statuses/show',
          status: :created,
          location: '/issue_statuses.json'
        )

        controller.create
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(issue_status)

          controller.create
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end

      context 'when the request does not use the extended API prefix' do
        before do
          allow(controller).to receive(:extended_api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end
    end

    describe '#update' do
      let(:controller) { controller_class.new }
      let(:issue_status) { double('IssueStatus', errors: ErrorsStub.new) }
      let(:save_result) { true }

      before do
        controller.params = { id: '3', issue_status: { name: 'In progress' } }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)

        stub_const('IssueStatus', issue_status_class)
        allow(IssueStatus).to receive(:find).with('3').and_return(issue_status)
        allow(issue_status).to receive(:safe_attributes=)
        allow(issue_status).to receive(:save).and_return(save_result)
      end

      it 'updates the issue status when saving succeeds' do
        expect(issue_status).to receive(:safe_attributes=).with({ name: 'In progress' })
        expect(controller).to receive(:render_extended_api).with('issue_statuses/show')

        controller.update
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(issue_status)

          controller.update
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'delegates to the original action' do
          expect(controller.update).to eq(:base_update)
          expect(controller.super_calls[:update]).to eq(1)
        end
      end
    end

    describe '#destroy' do
      let(:controller) { controller_class.new }
      let(:issue_status) { double('IssueStatus', errors: ErrorsStub.new) }
      let(:destroy_result) { true }

      before do
        controller.params = { id: '5' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_api_validation_errors)
        allow(controller).to receive(:head)

        stub_const('IssueStatus', issue_status_class)
        allow(IssueStatus).to receive(:find).with('5').and_return(issue_status)
        allow(issue_status).to receive(:destroy).and_return(destroy_result)
      end

      it 'destroys the issue status when possible' do
        expect(controller).to receive(:head).with(:no_content)

        controller.destroy
      end

      context 'when destroy fails' do
        let(:destroy_result) { false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(issue_status)

          controller.destroy
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.destroy).to eq(:base_destroy)
          expect(controller.super_calls[:destroy]).to eq(1)
        end
      end
    end
  end

  describe RedmineExtendedApi::Patches::TrackersControllerPatch do
    let(:controller_class) { build_controller(described_class) }
    let(:tracker_class) do
      Class.new do
        class << self
          def find(_id)
            raise 'stubbed'
          end
        end
      end
    end
    let(:project_class) do
      Class.new do
        class << self
          def joins(_association)
            raise 'stubbed'
          end
        end
      end
    end

    before do
      unless defined?(ActionController)
        stub_const('ActionController', Module.new)
      end

      helpers_module = Module.new do
        def self.strip_tags(message)
          "stripped: #{message}"
        end
      end

      if ActionController.const_defined?(:Base)
        ActionController::Base.define_singleton_method(:helpers) { helpers_module }
      else
        base_class = Class.new do
          define_singleton_method(:helpers) { helpers_module }
        end

        ActionController.const_set(:Base, base_class)
      end
    end

    describe '.prepended' do
      it 'registers API auth actions' do
        expect(controller_class.accepted_actions).to match_array(%i[index show create update destroy])
      end

      it 'exposes the extended API metadata helper to the view layer' do
        expect(controller_class.helper_methods).to include(:extended_api_metadata)
      end
    end

    describe '#show' do
      let(:controller) { controller_class.new }
      let(:tracker) { double('Tracker') }

      before do
        controller.params = { id: '4' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_not_found)

        stub_const('Tracker', tracker_class)
        allow(Tracker).to receive(:find).with('4').and_return(tracker)
      end

      it 'finds the tracker and renders it' do
        expect(controller).to receive(:render_extended_api).with('trackers/show')

        controller.show

        expect(controller.super_calls[:show]).to eq(0)
      end

      context 'when the tracker cannot be found' do
        before do
          allow(Tracker).to receive(:find).and_raise(ActiveRecord::RecordNotFound, 'missing')
        end

        it 'renders a not found API response' do
          expect(controller).not_to receive(:render_extended_api)
          expect(controller).to receive(:render_api_not_found)

          controller.show
        end
      end
    end

    describe '#create' do
      let(:controller) { controller_class.new }
      let(:tracker) { double('Tracker', errors: ErrorsStub.new) }
      let(:save_result) { true }
      let(:request_format) { double(symbol: :json) }
      let(:request) { double('Request', format: request_format) }

      before do
        controller.params = { tracker: { name: 'Bug' }, copy_workflow_from: '7' }
        controller.request = request
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:trackers_url).with(format: :json).and_return('/trackers.json')
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)

        stub_const('Tracker', tracker_class)
        allow(Tracker).to receive(:new).and_return(tracker)
        allow(tracker).to receive(:safe_attributes=)
        allow(tracker).to receive(:save).and_return(save_result)
        allow(tracker).to receive(:copy_workflow_rules)
      end

      it 'saves the tracker and renders the template' do
        expect(tracker).to receive(:safe_attributes=).with({ name: 'Bug' })
        expect(controller).to receive(:copy_workflow_from_tracker).with(tracker, '7')
        expect(controller).to receive(:render_extended_api).with(
          'trackers/show',
          status: :created,
          location: '/trackers.json'
        )

        controller.create
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).not_to receive(:copy_workflow_from_tracker)
          expect(controller).to receive(:render_api_validation_errors).with(tracker)

          controller.create
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'falls back to the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end

      context 'when the request does not use the extended API prefix' do
        before do
          allow(controller).to receive(:extended_api_request?).and_return(false)
        end

        it 'falls back to the original implementation' do
          expect(controller.create).to eq(:base_create)
          expect(controller.super_calls[:create]).to eq(1)
        end
      end
    end

    describe '#update' do
      let(:controller) { controller_class.new }
      let(:tracker) { double('Tracker', errors: ErrorsStub.new) }
      let(:save_result) { true }

      before do
        controller.params = { id: '9', tracker: { name: 'Feature' } }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:render_extended_api)
        allow(controller).to receive(:render_api_validation_errors)

        stub_const('Tracker', tracker_class)
        allow(Tracker).to receive(:find).with('9').and_return(tracker)
        allow(tracker).to receive(:safe_attributes=)
        allow(tracker).to receive(:save).and_return(save_result)
      end

      it 'updates the tracker when saving succeeds' do
        expect(tracker).to receive(:safe_attributes=).with({ name: 'Feature' })
        expect(controller).to receive(:render_extended_api).with('trackers/show')

        controller.update
      end

      context 'when saving fails' do
        let(:save_result) { false }

        it 'renders validation errors' do
          expect(controller).to receive(:render_api_validation_errors).with(tracker)

          controller.update
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'delegates to the original action' do
          expect(controller.update).to eq(:base_update)
          expect(controller.super_calls[:update]).to eq(1)
        end
      end
    end

    describe '#destroy' do
      let(:controller) { controller_class.new }
      let(:issues_scope) { double('IssuesScope', empty?: issues_empty) }
      let(:tracker) { double('Tracker', id: 3, issues: issues_scope) }
      let(:issues_empty) { true }

      before do
        controller.params = { id: '3' }
        allow(controller).to receive(:extended_api_request?) { controller.api_request? }
        allow(controller).to receive(:api_request?).and_return(true)
        allow(controller).to receive(:head)
        allow(controller).to receive(:render_api_error_message)

        stub_const('Tracker', tracker_class)
        allow(Tracker).to receive(:find).with('3').and_return(tracker)
        allow(tracker).to receive(:destroy)
      end

      it 'destroys the tracker when there are no issues' do
        expect(tracker).to receive(:destroy)
        expect(controller).to receive(:head).with(:no_content)

        controller.destroy
      end

      context 'when the tracker still has issues' do
        let(:issues_empty) { false }
        let(:projects_scope) { double('ProjectsScope') }
        let(:where_scope) { double('WhereScope') }
        let(:sorted_scope) { double('SortedScope') }
        let(:distinct_scope) { double('DistinctScope') }

        before do
          stub_const('Project', project_class)
          allow(Project).to receive(:joins).with(:issues).and_return(projects_scope)
          allow(projects_scope).to receive(:where).with(issues: { tracker_id: 3 }).and_return(where_scope)
          allow(where_scope).to receive(:sorted).and_return(sorted_scope)
          allow(sorted_scope).to receive(:distinct).and_return(distinct_scope)
          allow(distinct_scope).to receive(:map).and_return(['Project A'])
          allow(I18n).to receive(:t).and_return('raw message')
          allow(controller).to receive(:render_api_error_message)
        end

        it 'renders an error message with the sanitized text' do
          expect(controller).to receive(:render_api_error_message).with('stripped: raw message')

          controller.destroy
        end
      end

      context 'when the request is not an API request' do
        before do
          allow(controller).to receive(:api_request?).and_return(false)
        end

        it 'calls the original implementation' do
          expect(controller.destroy).to eq(:base_destroy)
          expect(controller.super_calls[:destroy]).to eq(1)
        end
      end
    end
  end
end

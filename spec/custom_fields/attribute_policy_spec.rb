# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/redmine_extended_api/custom_fields/attribute_policy'

RSpec.describe RedmineExtendedApi::CustomFields::AttributePolicy do
  describe '#display_attribute?' do
    let(:format) do
      instance_double(
        'Format',
        is_filter_supported: true,
        searchable_supported: true,
        multiple_supported: true
      )
    end

    let(:issue_custom_field_class) do
      Class.new do
        attr_accessor :field_format, :format

        def initialize(field_format:, format:)
          @field_format = field_format
          @format = format
        end

        def self.name
          'IssueCustomField'
        end

        def self.customized_class
          Struct.new(:name).new('Issue')
        end
      end
    end

    let(:custom_field) do
      issue_custom_field_class.new(field_format: 'list', format: format)
    end

    it 'marks issue-specific attributes as visible for list fields' do
      policy = described_class.new(custom_field)

      expect(policy.display_attribute?(:possible_values)).to be(true)
      expect(policy.display_attribute?(:roles)).to be(true)
      expect(policy.display_attribute?(:trackers)).to be(true)
      expect(policy.display_attribute?(:projects)).to be(true)
      expect(policy.display_attribute?(:is_filter)).to be(true)
      expect(policy.display_attribute?(:searchable)).to be(true)
      expect(policy.display_attribute?(:multiple)).to be(true)
    end
  end

  describe '#assignable_attributes' do
    before do
      stub_const('RedmineDependingCustomFields', Module.new)
      stub_const('RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER', 'extended_user')
      stub_const('RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST', 'depending_list')
      stub_const('RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION', 'depending_enumeration')
    end

    let(:format) do
      instance_double(
        'Format',
        is_filter_supported: true,
        searchable_supported: false,
        multiple_supported: false
      )
    end

    let(:user_custom_field_class) do
      Class.new do
        attr_accessor :field_format, :format

        def initialize(field_format:, format:)
          @field_format = field_format
          @format = format
        end

        def self.name
          'UserCustomField'
        end

        def self.customized_class
          nil
        end
      end
    end

    let(:custom_field) do
      user_custom_field_class.new(field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER, format: format)
    end

    it 'returns plugin-specific attributes for extended user fields' do
      policy = described_class.new(custom_field)

      expect(policy.assignable_attributes).to include(:group_ids, :exclude_admins, :show_active, :show_registered, :show_locked)
      expect(policy.assignable_attributes).not_to include(:possible_values)
    end
  end

  describe '#boolean_value' do
    let(:format) do
      instance_double(
        'Format',
        is_filter_supported: false,
        searchable_supported: false,
        multiple_supported: false
      )
    end

    let(:project_custom_field_class) do
      Class.new do
        attr_accessor :field_format, :format

        def initialize(field_format:, format:)
          @field_format = field_format
          @format = format
        end

        def self.name
          'ProjectCustomField'
        end

        def self.customized_class
          Struct.new(:name).new('Project')
        end
      end
    end

    let(:custom_field) do
      project_custom_field_class.new(field_format: 'string', format: format)
    end

    it 'normalises boolean values using ActiveModel casting' do
      policy = described_class.new(custom_field)

      expect(policy.boolean_value(:is_required, '1')).to be(true)
      expect(policy.boolean_value(:is_required, '0')).to be(false)
      expect(policy.boolean_value(:name, 'anything')).to eq('anything')
    end
  end
end

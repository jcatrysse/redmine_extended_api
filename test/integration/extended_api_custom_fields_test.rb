# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# SD-18 to SD-21 of redmine_depending_custom_fields (docs/specs/large_lists_defects.md, WP-33).
# The depending cases run when redmine_depending_custom_fields is installed.
class ExtendedApiCustomFieldsTest < Redmine::ApiTest::Base
  TEST_FORMAT = 'extended_api_test_enumeration'

  # A format built on core's Key/Value list, like the Key/Value list (depending).
  class TestEnumerationFormat < Redmine::FieldFormat::EnumerationFormat
  end

  def setup
    super
    TestEnumerationFormat.send(:add, TEST_FORMAT)
  end

  def teardown
    Redmine::FieldFormat.delete(TEST_FORMAT)
    super
  end

  def depending_enumeration_format
    skip 'needs redmine_depending_custom_fields' unless defined?(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION)

    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
  end

  def parse_xml(body)
    Nokogiri::XML(body) { |config| config.strict }
  end

  def json
    ActiveSupport::JSON.decode(response.body)
  end

  def create_with_enumerations(field_format)
    post '/extended_api/custom_fields.json',
         params: {type: 'IssueCustomField',
                  custom_field: {name: "Entries #{field_format[0, 20]}", field_format: field_format,
                                 enumerations: [{name: 'Alpha'}, {name: 'Beta'}]}},
         headers: credentials('admin')
    assert_response :created
    field = CustomField.find(json['custom_field']['id'])
    assert_equal %w[Alpha Beta], field.enumerations.order(:position).map(&:name)
    assert_equal %w[Alpha Beta], json['custom_field']['enumerations'].map { |e| e['name'] }

    put "/extended_api/custom_fields/#{field.id}.json",
        params: {custom_field: {enumerations: [{name: 'Gamma'}]}}, headers: credentials('admin')
    assert_response :success
    assert_equal %w[Alpha Beta Gamma], field.enumerations.reload.order(:position).map(&:name)
    assert_equal %w[Alpha Beta Gamma], json['custom_field']['enumerations'].map { |e| e['name'] }
  end

  # SD-18: only field_format "enumeration" took enumerations; 201/200 with "enumerations": [].
  def test_enumerations_of_a_format_built_on_the_key_value_list
    create_with_enumerations(TEST_FORMAT)
  end

  def test_enumerations_of_the_depending_key_value_list
    create_with_enumerations(depending_enumeration_format)
  end

  # SD-19: the mappings were written as attributes, invalid for a parent value such as "a]",
  # "1" or one with a space. JSON keeps the objects.
  def test_dependency_mappings_in_xml_are_elements_and_json_is_unchanged
    format = depending_enumeration_format
    parent = IssueCustomField.create!(name: 'Country', field_format: 'list',
                                      possible_values: ['Belgium', 'a]', '1', 'Two words'])
    child = IssueCustomField.new(name: 'City', field_format: format)
    child.save!
    %w[Antwerp Paris Ghent].each_with_index do |name, i|
      child.enumerations.create!(name: name, position: i + 1)
    end
    ids = child.enumerations.order(:position).map { |e| e.id.to_s }
    dependencies = {'Belgium' => [ids[0], ids[2]], 'a]' => [ids[1]], '1' => [ids[0]], 'Two words' => [ids[2]]}
    defaults = {'Belgium' => ids[0], 'a]' => [ids[1]]}
    child.parent_custom_field_id = parent.id
    child.value_dependencies = dependencies
    child.default_value_dependencies = defaults
    child.save!
    child.reload
    stored_dependencies = child.value_dependencies
    stored_defaults = child.default_value_dependencies
    assert_equal 4, stored_dependencies.size

    get "/extended_api/custom_fields/#{child.id}.xml", headers: credentials('admin')
    assert_response :success
    doc = parse_xml(response.body)
    assert_equal 'custom_field', doc.root.name
    entries = doc.xpath('/custom_field/value_dependencies/value_dependency')
    assert_equal 'array', doc.at_xpath('/custom_field/value_dependencies')['type']
    assert_equal stored_dependencies,
                 entries.to_h { |e| [e['parent'], e.xpath('value').map(&:text)] }
    default_entries = doc.xpath('/custom_field/default_value_dependencies/default_value_dependency')
    assert_equal stored_defaults.transform_values { |v| Array(v) },
                 default_entries.to_h { |e| [e['parent'], e.xpath('value').map(&:text)] }

    get "/extended_api/custom_fields/#{child.id}.json", headers: credentials('admin')
    assert_response :success
    assert_equal stored_dependencies, json['custom_field']['value_dependencies']
    assert_equal stored_defaults, json['custom_field']['default_value_dependencies']
    assert_includes response.body, %("value_dependencies":#{stored_dependencies.to_json})
  end

  # SD-20: a controller that never called accept_api_auth has a nil list; the proxy raised 500.
  def test_proxy_answers_not_a_rest_endpoint_for_a_controller_without_api_authentication
    %w[/extended_api/settings.json /extended_api/admin/projects.json /extended_api/settings.xml].each do |path|
      get path, headers: credentials('admin')
      assert_response :not_found
      assert_equal({'error' => 'Not a REST API endpoint'}, json, path)
    end
  end

  # SD-21 (1): core's build_new_custom_field assigned every safe attribute of the request before
  # the AttributePolicy filtered them, so create took what update drops.
  def test_create_applies_only_the_attributes_of_the_policy
    post '/extended_api/custom_fields.json',
         params: {type: 'IssueCustomField',
                  custom_field: {name: 'Policy only', field_format: 'string', max_length: '20',
                                 possible_values: %w[Leaked], multiple: '1', edit_tag_style: 'check_box'}},
         headers: credentials('admin')
    assert_response :created
    field = CustomField.find(json['custom_field']['id'])
    assert_equal 'Policy only', field.name
    assert_equal 'string', field.field_format
    assert_equal 20, field.max_length
    assert_equal [], Array(field.possible_values)
    assert_equal false, field.multiple?
    assert_nil field.edit_tag_style.presence

    put "/extended_api/custom_fields/#{field.id}.json",
        params: {custom_field: {possible_values: %w[Leaked], multiple: '1', edit_tag_style: 'check_box'}},
        headers: credentials('admin')
    assert_response :success
    field.reload
    assert_equal [], Array(field.possible_values)
    assert_equal false, field.multiple?
    assert_nil field.edit_tag_style.presence
  end

  # custom_field as an Array: Array#to_h raised TypeError, a 500 on create and update
  def test_custom_field_that_is_no_hash_is_a_validation_error
    assert_no_difference 'CustomField.count' do
      post '/extended_api/custom_fields.json', params: {type: 'IssueCustomField', custom_field: %w[a b]},
                                               headers: credentials('admin')
    end
    assert_response 422

    put '/extended_api/custom_fields/1.json', params: {custom_field: %w[a b]}, headers: credentials('admin')
    assert_response :success
    assert_equal 'Database', CustomField.find(1).name
  end

  def test_create_with_copy_and_format_from_the_request
    post '/extended_api/custom_fields.json',
         params: {type: 'IssueCustomField', copy: 1, custom_field: {name: 'Copied', field_format: 'list',
                                                                     possible_values: %w[A B]}},
         headers: credentials('admin')
    assert_response :created
    field = CustomField.find(json['custom_field']['id'])
    assert_equal %w[A B], field.possible_values
    assert_equal CustomField.find(1).tracker_ids.sort, field.tracker_ids.sort
  end

  # SD-21 (2): accept_api_auth of the Extended API also opened core's own paths: an admin key
  # created, saved or deleted there and then answered 302 or 406. Core takes a key for index only.
  def test_core_custom_field_paths_take_no_api_key_for_writes
    field = CustomField.find(1)

    assert_no_difference 'CustomField.count' do
      post '/custom_fields.json', params: {type: 'IssueCustomField', custom_field: {name: 'Core path', field_format: 'string'}},
                                  headers: credentials('admin')
    end
    assert_response :forbidden

    put "/custom_fields/#{field.id}.json", params: {custom_field: {name: 'Renamed on core path'}},
                                           headers: credentials('admin')
    assert_response :forbidden
    assert_not_equal 'Renamed on core path', field.reload.name

    assert_no_difference 'CustomField.count' do
      delete "/custom_fields/#{field.id}.json", headers: credentials('admin')
    end
    assert_response :forbidden

    get '/custom_fields.json', headers: credentials('admin')
    assert_response :success

    put "/extended_api/custom_fields/#{field.id}.json", params: {custom_field: {name: 'Renamed'}},
                                                        headers: credentials('admin')
    assert_response :success
    assert_equal 'Renamed', field.reload.name
  end

  # group_ids of the extended user format: an Array given to the XML builder was Ruby text.
  def test_group_ids_in_xml_are_elements_and_json_is_unchanged
    skip 'needs redmine_depending_custom_fields' unless defined?(RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER)

    field = IssueCustomField.new(name: 'Xml users', field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER)
    field.group_ids = %w[10 11]
    field.save!

    get "/extended_api/custom_fields/#{field.id}.xml", headers: credentials('admin')
    assert_response :success
    list = parse_xml(response.body).at_xpath('/custom_field/group_ids')
    assert_equal 'array', list['type']
    assert_equal %w[10 11], list.xpath('group_id').map(&:text)

    get "/extended_api/custom_fields/#{field.id}.json", headers: credentials('admin')
    assert_response :success
    assert_includes response.body, '"group_ids":[10,11]'
  end
end

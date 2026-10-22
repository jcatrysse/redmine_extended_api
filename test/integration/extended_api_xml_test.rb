# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# The views of this plugin wrote the extended_api metadata as a second top-level element, so no
# XML parser accepted an .xml answer. XML now has one root element; JSON is unchanged (the Jira
# migration scripts read it).
class ExtendedApiXmlTest < Redmine::ApiTest::Base
  RECORDS = {
    'custom_field' => '/extended_api/custom_fields/1',
    'enumeration' => '/extended_api/enumerations/4',
    'issue_status' => '/extended_api/issue_statuses/1',
    'tracker' => '/extended_api/trackers/1'
  }.freeze

  def parse_xml(body)
    Nokogiri::XML(body) { |config| config.strict }
  end

  def test_record_answers_have_one_root_with_the_metadata_inside
    RECORDS.each do |root, path|
      get "#{path}.xml", headers: credentials('admin')
      assert_response :success

      doc = parse_xml(response.body)
      assert_equal root, doc.root.name, path
      assert_equal 'extended', doc.at_xpath("/#{root}/extended_api/mode")&.text, path
      assert_equal 'false', doc.at_xpath("/#{root}/extended_api/fallback_to_native")&.text, path
      assert doc.at_xpath("/#{root}/id"), path
    end
  end

  def test_written_record_answers_have_one_root
    post '/extended_api/roles.xml', params: {role: {name: 'Xml role', permissions: %w[view_issues]}},
                                    headers: credentials('admin')
    assert_response :created
    assert_equal 'Xml role', parse_xml(response.body).at_xpath('/role/name')&.text

    put '/extended_api/issues/1.xml', params: {issue: {notes: 'Xml note'}}, headers: credentials('admin')
    assert_response :success
    doc = parse_xml(response.body)
    assert_equal 'journal', doc.root.name
    assert_equal 'extended', doc.at_xpath('/journal/extended_api/mode')&.text
    assert_equal 'Xml note', doc.at_xpath('/journal/notes')&.text
  end

  def test_enumeration_list_has_one_root_with_the_metadata_as_attributes
    get '/extended_api/enumerations.xml', params: {type: 'issue_priorities'}, headers: credentials('admin')
    assert_response :success

    doc = parse_xml(response.body)
    assert_equal 'enumerations', doc.root.name
    assert_equal 'extended', doc.root['extended_api_mode']
    assert_equal 'false', doc.root['extended_api_fallback_to_native']
    assert_equal IssuePriority.count, doc.xpath('/enumerations/enumeration').size
    # what Rails clients (Hash.from_xml, ActiveResource) read from a type="array" element
    assert_equal IssuePriority.count, Hash.from_xml(response.body)['enumerations'].size

    get '/extended_api/enumerations.xml', params: {type: 'issue_priorities', nometa: 1},
                                          headers: credentials('admin')
    assert_nil parse_xml(response.body).root['extended_api_mode']
  end

  def test_json_keeps_the_metadata_at_the_top_level
    RECORDS.each do |root, path|
      get "#{path}.json", headers: credentials('admin')
      json = ActiveSupport::JSON.decode(response.body)
      assert_equal ['extended_api', root], json.keys, path
      assert_equal({'mode' => 'extended', 'fallback_to_native' => false}, json['extended_api'])
    end

    get '/extended_api/enumerations.json', params: {type: 'issue_priorities'}, headers: credentials('admin')
    assert_equal %w[extended_api enumerations], ActiveSupport::JSON.decode(response.body).keys
  end
end

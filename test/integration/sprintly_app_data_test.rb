# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# SPR-553: "App data" (the SPA's dashboards and saved filters) is its owner's only.
#
# Fixtures used: jsmith (2) owns the data; dlopper (3) is another user; admin (1) is a Redmine
# administrator. jsmith also has a "Phone number" (user field 4), which stays public.
class SprintlyAppDataTest < Redmine::ApiTest::Base
  AppData = RedmineExtendedApi::Sprintly::AppData

  PASSWORDS = { 'dlopper' => 'foo' }.freeze
  SECRET = '{"version":1,"savedFilters":[{"name":"Payroll","q":"salary review"}],"dashboards":[]}'

  def auth(login)
    credentials(login, PASSWORDS[login])
  end

  def json_headers(login)
    auth(login).merge('CONTENT_TYPE' => 'application/json')
  end

  def read_app_data(login, path = '/sprintly/me/app_data.json')
    get path, headers: auth(login)
    assert_response :success
    JSON.parse(response.body)['app_data']
  end

  def write_app_data(login, value, digest: nil, path: '/sprintly/me/app_data.json')
    body = { app_data: { value: value } }
    body[:app_data][:digest] = digest if digest
    put path, params: body.to_json, headers: json_headers(login)
  end

  def store_secret_for_jsmith
    write_app_data('jsmith', SECRET)
    assert_response :success
  end

  def app_data_in(custom_fields)
    (custom_fields || []).find { |cf| cf['name'] == AppData::FIELD_NAME }
  end

  def user_fields(login, path)
    get path, headers: auth(login)
    assert_response :success
    JSON.parse(response.body)['user']['custom_fields']
  end

  test 'a user without data reads null, and the first write creates the field for a non-administrator' do
    assert_empty AppData.fields
    data = read_app_data('dlopper')
    assert_nil data['value']
    assert_equal AppData.digest(nil), data['digest']

    write_app_data('dlopper', '{"version":1,"dashboards":[]}')
    assert_response :success
    field = AppData.fields.first
    assert field, 'the field is created'
    assert_equal 'text', field.field_format
    assert_equal '{"version":1,"dashboards":[]}', read_app_data('dlopper')['value']
  end

  test 'the owner reads and writes the value, also through the proxy' do
    store_secret_for_jsmith
    assert_equal SECRET, read_app_data('jsmith')['value']

    data = read_app_data('jsmith', '/extended_api/sprintly/me/app_data.json')
    assert_equal SECRET, data['value']
    write_app_data('jsmith', '{"version":1}', digest: data['digest'], path: '/extended_api/sprintly/me/app_data.json')
    assert_response :success
    assert_equal '{"version":1}', JSON.parse(response.body).dig('app_data', 'value')
    assert_equal '{"version":1}', read_app_data('jsmith')['value']
  end

  test 'nobody reads another user\'s value through the endpoint' do
    store_secret_for_jsmith
    assert_nil read_app_data('dlopper')['value']
    assert_nil read_app_data('admin')['value']
  end

  test 'another user does not get the value in /users/:id.json, other fields stay' do
    store_secret_for_jsmith
    fields = user_fields('dlopper', '/users/2.json')
    assert_nil app_data_in(fields)
    assert_equal '01 42 50 00 00', fields.find { |cf| cf['id'] == 4 }&.dig('value')
    refute_includes response.body, 'salary review'
  end

  test 'administrators do not get it either, neither in /users/:id.json nor in /users.json' do
    store_secret_for_jsmith
    assert_nil app_data_in(user_fields('admin', '/users/2.json'))
    refute_includes response.body, 'salary review'

    get '/users.json', headers: auth('admin')
    assert_response :success
    jsmith = JSON.parse(response.body)['users'].find { |u| u['id'] == 2 }
    assert_nil app_data_in(jsmith['custom_fields'])
    refute_includes response.body, 'salary review'
  end

  test 'the owner still gets it in /my/account.json and /users/current.json (the SPA before SPR-553)' do
    store_secret_for_jsmith
    assert_equal SECRET, app_data_in(user_fields('jsmith', '/my/account.json'))&.dig('value')
    assert_equal SECRET, app_data_in(user_fields('jsmith', '/users/current.json'))&.dig('value')
    assert_equal SECRET, app_data_in(user_fields('jsmith', '/users/2.json'))&.dig('value')
  end

  test 'the user directory does not carry it' do
    store_secret_for_jsmith
    get '/sprintly/principals.json', headers: auth('dlopper')
    assert_response :success
    refute_includes response.body, 'salary review'
  end

  test 'the profile page does not show it to another user' do
    store_secret_for_jsmith
    log_user('dlopper', 'foo')
    get '/users/2'
    assert_response :success
    refute_includes response.body, 'salary review'
  end

  test 'a write over a value changed since it was read is refused with the current value' do
    store_secret_for_jsmith
    stale = AppData.digest(nil)
    write_app_data('jsmith', '{"version":1,"dashboards":[{"id":"x"}]}', digest: stale)
    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal SECRET, body.dig('app_data', 'value')
    assert_equal AppData.digest(SECRET), body.dig('app_data', 'digest')
    assert_equal SECRET, read_app_data('jsmith')['value']

    write_app_data('jsmith', '{"version":1,"dashboards":[{"id":"x"}]}', digest: body.dig('app_data', 'digest'))
    assert_response :success
  end

  test 'a value that is not a JSON object, or too large, is refused' do
    ['not json', '[1,2]', '"text"', '', '{"a":"' + ('x' * AppData::MAX_BYTES) + '"}'].each do |value|
      write_app_data('jsmith', value)
      assert_response :unprocessable_entity, value.first(20)
    end
    put '/sprintly/me/app_data.json', params: { app_data: {} }.to_json, headers: json_headers('jsmith')
    assert_response :unprocessable_entity
    put '/sprintly/me/app_data.json', params: { app_data: { value: { a: 1 } } }.to_json, headers: json_headers('jsmith')
    assert_response :unprocessable_entity
    assert_nil read_app_data('jsmith')['value']
  end

  test 'anonymous requests are refused' do
    get '/sprintly/me/app_data.json'
    assert_response :unauthorized
    put '/sprintly/me/app_data.json', params: { app_data: { value: '{}' } }.to_json,
                                      headers: { 'CONTENT_TYPE' => 'application/json' }
    assert_response :unauthorized
  end

  test 'works the same when the field is hidden' do
    store_secret_for_jsmith
    AppData.fields.first.update!(visible: false)
    data = read_app_data('jsmith')
    assert_equal SECRET, data['value']
    write_app_data('jsmith', '{"version":1}', digest: data['digest'])
    assert_response :success
    assert_equal '{"version":1}', read_app_data('jsmith')['value']
    assert_nil app_data_in(user_fields('dlopper', '/users/2.json'))
  end

  test 'a field the SPA created earlier is reused, the one holding data wins' do
    first = UserCustomField.create!(name: AppData::FIELD_NAME, field_format: 'text', visible: true)
    CustomValue.create!(customized: User.find(2), custom_field: first, value: SECRET)
    assert_equal SECRET, read_app_data('jsmith')['value']
    write_app_data('jsmith', '{"version":1}')
    assert_response :success
    assert_equal 1, AppData.fields.size
    assert_equal '{"version":1}', User.find(2).custom_field_value(first)
  end
end

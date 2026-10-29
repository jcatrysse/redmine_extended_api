# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# SPR-521: a wiki page's history, diff and annotate as JSON, over the REST API.
#
# Fixtures used: project 1 (ecookbook, public) whose page CookBook_documentation has versions
# 1 (jsmith, "Page creation"), 2 (admin, "Small update") and 3 (admin, no comment); jsmith (2)
# is a Manager and dlopper (3) a Developer there. Project 2 (onlinestore) is private and
# dlopper is not a member.
class SprintlyWikiHistoryTest < Redmine::ApiTest::Base
  PASSWORDS = { 'dlopper' => 'foo' }.freeze

  def setup
    super
    RedmineExtendedApi::Sprintly::Store.clear!
  end

  def auth(login)
    credentials(login, PASSWORDS[login] || login)
  end

  def json_headers(login)
    auth(login).merge('CONTENT_TYPE' => 'application/json')
  end

  def body
    JSON.parse(response.body)
  end

  def save_page(title, text, login, comments = '')
    put "/projects/ecookbook/wiki/#{title}.json",
        params: { wiki_page: { text: text, comments: comments } }.to_json, headers: json_headers(login)
    assert_includes [201, 204], response.status
  end

  V1 = '<h2>Deploy</h2><p>Run the old script</p>' \
       '<table><tbody><tr><th><p>Env</p></th><th><p>Owner</p></th></tr></tbody></table>'
  V2 = '<h2>Deploy</h2><p>Run the new&nbsp;script</p><p>Done</p>' \
       '<table><tbody><tr><th><p>Env</p></th><th><p>Owner</p></th></tr></tbody></table>'

  def html_page
    save_page('Html_page', V1, 'jsmith', 'first')
    save_page('Html_page', V2, 'admin', 'second')
  end

  def test_history_lists_versions_newest_first_without_text
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/history.json', headers: auth('dlopper')
    assert_response :success
    assert_equal({ 'title' => 'CookBook_documentation', 'version' => 3 }, body['wiki_page'])
    assert_equal 3, body['total_count']
    assert_equal [3, 2, 1], body['versions'].map { |v| v['version'] }
    first = body['versions'].last
    assert_equal({ 'id' => 2, 'name' => 'John Smith' }, first['author'])
    assert_equal 'Page creation', first['comments']
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, first['updated_on'])
    assert_equal '', body['versions'].first['comments']
    refute body['versions'].first.key?('text')
  end

  def test_history_pages_with_limit_and_offset
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/history.json?limit=2&offset=1', headers: auth('dlopper')
    assert_response :success
    assert_equal [2, 1], body['versions'].map { |v| v['version'] }
    assert_equal 3, body['total_count']
    assert_equal 1, body['offset']
    assert_equal 2, body['limit']
  end

  def test_diff_compares_blocks_of_html_versions
    html_page
    get '/sprintly/projects/ecookbook/wiki/Html_page/diff.json', headers: auth('dlopper')
    assert_response :success
    diff = body['wiki_diff']
    assert_equal 'Html_page', diff['title']
    assert_equal 1, diff['version_from']['version']
    assert_equal 'first', diff['version_from']['comments']
    assert_equal 2, diff['version_to']['version']
    assert_equal 'Redmine Admin', diff['version_to']['author']['name']
    assert_equal [
      %w[equal Deploy], ['delete', 'Run the old script'], ['insert', 'Run the new script'],
      %w[insert Done], ['equal', 'Env | Owner']
    ], diff['blocks'].map { |b| [b['op'], b['text']] }
  end

  def test_diff_takes_any_two_versions_older_first
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/diff.json?version=1&version_from=3', headers: auth('jsmith')
    assert_response :success
    assert_equal 1, body['wiki_diff']['version_from']['version']
    assert_equal 3, body['wiki_diff']['version_to']['version']
    assert body['wiki_diff']['blocks'].any? { |b| b['op'] != 'equal' }
  end

  def test_diff_of_the_first_version_or_a_missing_one_is_not_found
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/diff.json?version=1', headers: auth('jsmith')
    assert_response :not_found
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/diff.json?version=9', headers: auth('jsmith')
    assert_response :not_found
  end

  def test_annotate_gives_each_block_its_version_and_author
    html_page
    get '/sprintly/projects/ecookbook/wiki/Html_page/annotate.json', headers: auth('dlopper')
    assert_response :success
    annotate = body['wiki_annotate']
    assert_equal 2, annotate['version']
    assert_equal [
      ['Deploy', 1, 'John Smith'], ['Run the new script', 2, 'Redmine Admin'], ['Done', 2, 'Redmine Admin'],
      ['Env | Owner', 1, 'John Smith']
    ], annotate['lines'].map { |l| [l['text'], l['version'], l['author']['name']] }

    get '/sprintly/projects/ecookbook/wiki/Html_page/annotate.json?version=1', headers: auth('dlopper')
    assert_equal ['Deploy', 'Run the old script', 'Env | Owner'], body['wiki_annotate']['lines'].map { |l| l['text'] }
  end

  def test_needs_view_wiki_edits
    Role.find(2).remove_permission!(:view_wiki_edits)
    %w[history diff annotate].each do |action|
      get "/sprintly/projects/ecookbook/wiki/CookBook_documentation/#{action}.json", headers: auth('dlopper')
      assert_response :forbidden, action
    end
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/history.json', headers: auth('jsmith')
    assert_response :success
  end

  def test_a_private_project_or_a_missing_page
    get '/sprintly/projects/onlinestore/wiki/Start_page/history.json', headers: auth('dlopper')
    assert_response :forbidden
    get '/sprintly/projects/ecookbook/wiki/No_such_page/history.json', headers: auth('dlopper')
    assert_response :not_found
    get '/sprintly/projects/nope/wiki/CookBook_documentation/history.json', headers: auth('dlopper')
    assert_response :not_found
  end

  def test_with_the_sprintly_role_model_wiki_view_brings_history
    post '/sprintly/import.json', headers: json_headers('admin'), params: {
      import: {
        roles: [
          { key: 'admin', name: 'Administrator', permissions: RedmineExtendedApi::Sprintly::Permissions::APP_PERMISSIONS, preset: 'admin' },
          { key: 'blind', name: 'Blind', permissions: %w[projects.view issues.view], preset: 'viewer' }
        ],
        users: { '2' => ['admin'], '3' => ['blind'] }, groups: {}, default_role: 'blind', projects: {}
      }
    }.to_json
    assert_response :success
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/history.json', headers: auth('jsmith')
    assert_response :success
    get '/sprintly/projects/ecookbook/wiki/CookBook_documentation/history.json', headers: auth('dlopper')
    assert_response :forbidden
  end

  def test_reachable_through_the_extended_api_prefix
    get '/extended_api/sprintly/projects/ecookbook/wiki/CookBook_documentation/history.json', headers: auth('dlopper')
    assert_response :success
    assert_equal 3, body['total_count']
  end

  def test_blocks_of_legacy_text_and_html
    blocks = RedmineExtendedApi::Sprintly::WikiBlocks
    assert_equal ['h1. Title', 'Some text'], blocks.blocks_of("h1. Title\r\n\r\nSome   text\n")
    assert_equal ['a', 'b', 'x = 1', 'y = 2', 'one', 'nested'],
                 blocks.blocks_of('<p>a<br>b</p><p> </p><pre><code>x = 1' + "\n" + 'y = 2</code></pre>' \
                                  '<script>alert(1)</script><ul><li><p>one</p><ul><li>nested</li></ul></li></ul>')
    assert_equal ['Olena K. | QA & dev'], blocks.blocks_of('<table><tr><td>Olena&nbsp;K.</td><td>QA &amp; dev</td></tr></table>')
    assert_equal [], blocks.blocks_of(nil)
  end
end

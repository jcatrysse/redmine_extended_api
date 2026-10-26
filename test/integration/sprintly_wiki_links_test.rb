# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# SPR-524: "Linked from" of a wiki page in one request.
#
# Fixtures used: project 1 (ecookbook, public) owns wiki 1 with pages 1 CookBook_documentation,
# 2 Another_page, 4 Page_with_an_inline_image, 5 Child_1, 6 Child_2, 10 Этика_менеджмента;
# project 2 (onlinestore, private) owns wiki 2 (page 3 Start_page). dlopper (3) is a Developer
# of project 1 only.
class SprintlyWikiLinksTest < Redmine::ApiTest::Base
  def set_text(page_id, text)
    WikiContent.find_by!(page_id: page_id).update_column(:text, text)
  end

  def backlinks(title, project: 'ecookbook', login: 'jsmith', password: nil, prefix: '')
    get "#{prefix}/sprintly/projects/#{project}/wiki/backlinks.json", params: { title: title },
                                                                      headers: credentials(login, password)
  end

  def titles
    JSON.parse(response.body)['backlinks'].map { |b| b['title'] }
  end

  def test_pages_linking_to_a_page_in_any_spelling
    set_text 1, '<p>See [[Another page]] for more.</p>'
    set_text 4, '<p>[[another_page|the other one]] and [[Child_1]]</p>'
    set_text 5, '<p>Section link: [[Another_page#Usage]]</p>'
    set_text 6, '<p>Nothing linked, only [[Child_1]] and a [plain] bracket</p>'
    set_text 2, '<p>Self link [[Another page]]</p>'
    set_text 3, '<p>Other wiki: [[Another page]]</p>'

    backlinks 'Another_page'
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'Another_page', body['title']
    assert_equal %w[Child_1 CookBook_documentation Page_with_an_inline_image], titles
    child = body['backlinks'].find { |b| b['title'] == 'Child_1' }
    assert_equal 'Another_page', child['parent_title']
    assert child['updated_on'].present?
  end

  def test_title_in_the_url_form_with_spaces_and_cyrillic
    set_text 1, '<p>[[этика менеджмента|етика]] and [[Q&amp;A]]</p>'
    backlinks 'Этика менеджмента'
    assert_response :success
    assert_equal %w[CookBook_documentation], titles
  end

  def test_links_to_an_old_title_of_a_renamed_page_count
    WikiRedirect.create!(wiki_id: 1, title: 'Old_name', redirects_to: 'Another_page', redirects_to_wiki_id: 1)
    set_text 1, '<p>[[Old name]]</p>'
    backlinks 'Another_page'
    assert_response :success
    assert_equal %w[CookBook_documentation], titles
  end

  def test_nothing_links_here
    backlinks 'Child_2'
    assert_response :success
    assert_equal [], titles
  end

  def test_through_the_proxy_prefix
    set_text 1, '<p>[[Child 2]]</p>'
    backlinks 'Child_2', prefix: '/extended_api'
    assert_response :success
    assert_equal %w[CookBook_documentation], titles
  end

  def test_unknown_page_or_project_is_not_found
    backlinks 'No_such_page'
    assert_response :not_found
    backlinks 'Another_page', project: 'no-such-project'
    assert_response :not_found
  end

  def test_needs_view_wiki_pages_in_the_project
    backlinks 'Start_page', project: 'onlinestore', login: 'dlopper', password: 'foo'
    assert_response :forbidden

    Role.find(2).remove_permission!(:view_wiki_pages) # Developer
    backlinks 'Another_page', login: 'dlopper', password: 'foo'
    assert_response :forbidden
  end

  def test_project_without_a_wiki_is_not_found
    backlinks 'Anything', project: 'subproject1', login: 'admin'
    assert_response :not_found
  end
end

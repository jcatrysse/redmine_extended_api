# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# skip_journal (decision 37 of the Jira migration): an admin's post-processing through
# /extended_api leaves no journal and no edit trace. Each case next to the same request without
# the flag, which keeps today's journals.
class ExtendedApiSkipJournalTest < Redmine::ApiTest::Base
  OLD_TIME = Time.utc(2019, 4, 5, 6, 7, 8)

  def setup
    super
    @delivery_method = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    Issue.where(id: [1, 2, 3]).update_all(updated_on: OLD_TIME)
    # GEOxyz runs redmine_view_issue_description: without its permission jsmith (Manager on
    # project 1) cannot open issue 1, and the non-admin cases would be refused by that plugin
    if Redmine::Plugin.installed?(:redmine_view_issue_description)
      Role.find(1).add_permission!(:view_issue_description)
    end
  end

  def teardown
    ActionMailer::Base.delivery_method = @delivery_method
    super
  end

  def test_update_issue_with_skip_journal_stores_no_journal_and_keeps_updated_on
    assert_no_difference 'Journal.count' do
      put '/extended_api/issues/1.json?notify=false&skip_journal=1',
          params: {issue: {description: 'Relinked description', subject: 'Imported subject'}},
          headers: credentials('admin')
    end
    assert_response :no_content

    issue = Issue.find(1)
    assert_equal ['Relinked description', 'Imported subject'], [issue.description, issue.subject]
    assert_equal OLD_TIME, issue.updated_on.utc
    assert_nil Thread.current[:redmine_extended_api_skip_journal]
  end

  def test_update_issue_with_skip_journal_in_the_json_body
    assert_no_difference 'Journal.count' do
      put '/extended_api/issues/1.json',
          params: {issue: {description: 'From the body'}, notify: false, skip_journal: true}.to_json,
          headers: {'CONTENT_TYPE' => 'application/json'}.merge(credentials('admin'))
    end
    assert_response :no_content
    assert_equal 'From the body', Issue.find(1).description
    assert_equal OLD_TIME, Issue.find(1).updated_on.utc
  end

  def test_update_issue_with_skip_journal_and_updated_on_override_keeps_the_override
    assert_no_difference 'Journal.count' do
      put '/extended_api/issues/1.json?skip_journal=true',
          params: {issue: {description: 'Relinked', updated_on: '2021-05-06T07:08:09Z'}},
          headers: credentials('admin')
    end
    assert_response :no_content
    assert_equal Time.utc(2021, 5, 6, 7, 8, 9), Issue.find(1).updated_on.utc
  end

  def test_update_issue_without_skip_journal_stores_a_journal
    assert_difference 'Journal.count', 1 do
      put '/extended_api/issues/1.json?notify=false',
          params: {issue: {description: 'Relinked description'}},
          headers: credentials('admin')
    end
    assert_response :success
    assert Issue.find(1).updated_on > 1.hour.ago
  end

  def test_update_issue_with_skip_journal_false_stores_a_journal
    assert_difference 'Journal.count', 1 do
      put '/extended_api/issues/1.json?skip_journal=0',
          params: {issue: {description: 'Relinked description'}},
          headers: credentials('admin')
    end
    assert_response :success
  end

  # Notes live in a journal: with skip_journal they would be lost without a word.
  def test_update_issue_with_skip_journal_and_notes_is_refused
    assert_no_difference 'Journal.count' do
      put '/extended_api/issues/1.json?skip_journal=1',
          params: {issue: {description: 'Relinked', notes: 'a comment'}},
          headers: credentials('admin')
    end
    assert_response :unprocessable_entity
    assert_include 'Notes is invalid', ActiveSupport::JSON.decode(response.body)['errors']
    assert_not_equal 'Relinked', Issue.find(1).description
  end

  def test_set_parent_with_skip_journal_writes_no_subtask_added
    assert_no_difference 'Journal.count' do
      put '/extended_api/issues/2.json?notify=false&skip_journal=1',
          params: {issue: {parent_issue_id: 1}},
          headers: credentials('admin')
    end
    assert_response :no_content
    assert_equal 1, Issue.find(2).parent_id
    assert_equal OLD_TIME, Issue.find(1).updated_on.utc
    assert_equal OLD_TIME, Issue.find(2).updated_on.utc
  end

  def test_set_parent_without_skip_journal_writes_subtask_added
    put '/extended_api/issues/2.json?notify=false',
        params: {issue: {parent_issue_id: 1}},
        headers: credentials('admin')
    assert_response :success

    added = JournalDetail.joins(:journal).
      where(journals: {journalized_type: 'Issue', journalized_id: 1}, property: 'attr', prop_key: 'child_id')
    assert_equal ['2'], added.pluck(:value)
  end

  def test_create_subtask_with_skip_journal_writes_no_subtask_added_on_the_parent
    assert_no_difference 'Journal.count' do
      post '/extended_api/issues.json?notify=false&skip_journal=1',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Imported subtask', parent_issue_id: 1,
                            author_id: 3, created_on: '2020-01-02T03:04:05Z', updated_on: '2020-01-02T03:04:05Z'}},
           headers: credentials('admin')
    end
    assert_response :created

    child = Issue.order(:id).last
    assert_equal [1, 3, Time.utc(2020, 1, 2, 3, 4, 5)], [child.parent_id, child.author_id, child.updated_on.utc]
    assert_equal OLD_TIME, Issue.find(1).updated_on.utc
  end

  def test_create_subtask_without_skip_journal_writes_subtask_added_on_the_parent
    assert_difference 'Journal.where(journalized_type: "Issue", journalized_id: 1).count', 1 do
      post '/extended_api/issues.json?notify=false',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Imported subtask', parent_issue_id: 1}},
           headers: credentials('admin')
    end
    assert_response :created
  end

  def test_create_and_destroy_relation_with_skip_journal_store_no_journal
    assert_no_difference 'Journal.count' do
      post '/extended_api/issues/1/relations.json?notify=false&skip_journal=1',
           params: {relation: {issue_to_id: 3, relation_type: 'relates'}},
           headers: credentials('admin')
    end
    assert_response :created
    relation = IssueRelation.find(ActiveSupport::JSON.decode(response.body)['relation']['id'])

    assert_no_difference 'Journal.count' do
      delete "/extended_api/relations/#{relation.id}.json?notify=false&skip_journal=1", headers: credentials('admin')
    end
    assert_response :no_content
    assert_not IssueRelation.exists?(relation.id)
    assert_equal [OLD_TIME, OLD_TIME], Issue.where(id: [1, 3]).order(:id).map {|i| i.updated_on.utc}
  end

  def test_create_and_destroy_relation_without_skip_journal_store_journals_on_both_issues
    assert_difference 'Journal.count', 2 do
      post '/extended_api/issues/1/relations.json?notify=false',
           params: {relation: {issue_to_id: 3, relation_type: 'relates'}},
           headers: credentials('admin')
    end
    assert_response :created
    relation_id = ActiveSupport::JSON.decode(response.body)['relation']['id']

    assert_difference 'Journal.count', 2 do
      delete "/extended_api/relations/#{relation_id}.json?notify=false", headers: credentials('admin')
    end
    assert_response :no_content
  end

  def test_update_journal_with_skip_journal_keeps_updated_on_and_updated_by
    journal = Journal.find(1)
    journal.update_columns(updated_on: OLD_TIME, updated_by_id: 2)

    put '/extended_api/journals/1.json?skip_journal=1',
        params: {journal: {notes: 'Rewritten comment'}},
        headers: credentials('admin')
    assert_response :no_content

    journal.reload
    assert_equal 'Rewritten comment', journal.notes
    assert_equal [OLD_TIME, 2], [journal.updated_on.utc, journal.updated_by_id]
    assert_nil Thread.current[:redmine_extended_api_skip_journal]
  end

  def test_update_journal_without_skip_journal_marks_it_edited
    journal = Journal.find(1)
    journal.update_columns(updated_on: OLD_TIME, updated_by_id: 2)

    put '/extended_api/journals/1.json',
        params: {journal: {notes: 'Rewritten comment'}},
        headers: credentials('admin')
    assert_response :no_content

    journal.reload
    assert_equal 'Rewritten comment', journal.notes
    assert_equal 1, journal.updated_by_id
    assert journal.updated_on > 1.hour.ago
  end

  def test_skip_journal_as_non_admin_is_refused
    journal = Journal.find(1)
    journal.update_columns(updated_on: OLD_TIME, updated_by_id: 2)

    assert_no_difference ['Journal.count', 'IssueRelation.count'] do
      put '/extended_api/issues/1.json?skip_journal=1',
          params: {issue: {description: 'Not by jsmith'}},
          headers: credentials('jsmith')
      assert_response :forbidden
      post '/extended_api/issues.json?skip_journal=1',
           params: {issue: {project_id: 1, tracker_id: 1, subject: 'Not by jsmith', parent_issue_id: 1}},
           headers: credentials('jsmith')
      assert_response :forbidden
      post '/extended_api/issues/1/relations.json?skip_journal=1',
           params: {relation: {issue_to_id: 3, relation_type: 'relates'}},
           headers: credentials('jsmith')
      assert_response :forbidden
      put '/extended_api/journals/1.json?skip_journal=1',
          params: {journal: {notes: 'Not by jsmith'}},
          headers: credentials('jsmith')
      assert_response :forbidden
    end
    assert_not_equal 'Not by jsmith', Issue.find(1).description
    assert_not_equal 'Not by jsmith', journal.reload.notes
    assert_not Issue.where(subject: 'Not by jsmith').exists?
    assert_nil Thread.current[:redmine_extended_api_skip_journal]
  end

  def test_skip_journal_false_as_non_admin_behaves_as_today
    assert_difference 'Journal.count', 1 do
      put '/extended_api/issues/1.json?skip_journal=0',
          params: {issue: {description: 'By jsmith'}},
          headers: credentials('jsmith')
    end
    assert_response :success
  end

  # The flag belongs to /extended_api; core ignores it.
  def test_skip_journal_on_the_core_path_is_ignored
    assert_difference 'Journal.count', 1 do
      put '/issues/1.json?skip_journal=1',
          params: {issue: {description: 'Core path'}},
          headers: credentials('admin')
    end
    assert_response :no_content
  end
end

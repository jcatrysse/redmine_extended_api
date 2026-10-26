# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# SPR-525: a wiki page written through /extended_api with notify=false sends no mail —
# a bulk import used to mail every member of the project once per page.
class ExtendedApiWikiNotificationsTest < Redmine::ApiTest::Base
  include ActiveJob::TestHelper

  def setup
    super
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    # jsmith (a member of eCookbook) is told about everything in the project
    User.find(2).update_column(:mail_notification, 'all')
  end

  def teardown
    ActiveJob::Base.queue_adapter = @original_adapter
    super
  end

  # Mailer::DeliveryJob on Redmine 7, ActionMailer's own job before
  def wiki_mails(kind)
    enqueued_jobs.count { |j| j[:job].to_s.include?('DeliveryJob') && j[:args][1] == kind }
  end

  def put_page(path, text, params = {})
    put path, params: {wiki_page: {text: text}.merge(params)}, headers: credentials('jsmith')
  end

  def test_new_page_with_notify_false_mails_nobody_and_without_it_the_members_are_told
    with_settings notified_events: %w(wiki_content_added wiki_content_updated) do
      put_page '/extended_api/projects/ecookbook/wiki/Quiet_import.json?notify=false', 'imported'
      assert_response :created
      assert_equal 'imported', WikiPage.find_by(title: 'Quiet_import').content.text
      assert_equal 0, wiki_mails('wiki_content_added')

      put_page '/extended_api/projects/ecookbook/wiki/Loud_page.json', 'written by hand'
      assert_response :created
      assert_operator wiki_mails('wiki_content_added'), :>, 0
    end
  end

  def test_update_with_notify_false_in_the_page_params_mails_nobody
    with_settings notified_events: %w(wiki_content_added wiki_content_updated) do
      put_page '/extended_api/projects/ecookbook/wiki/CookBook_documentation.json', 'reimported', notify: 'false'
      assert_response :no_content
      assert_equal 'reimported', WikiPage.find_by(title: 'CookBook_documentation').content.text
      assert_equal 0, wiki_mails('wiki_content_updated')

      put_page '/extended_api/projects/ecookbook/wiki/CookBook_documentation.json', 'edited again'
      assert_response :no_content
      assert_operator wiki_mails('wiki_content_updated'), :>, 0
    end
  end

  def test_the_flag_does_not_outlive_its_request
    with_settings notified_events: %w(wiki_content_added) do
      put_page '/extended_api/projects/ecookbook/wiki/First_quiet.json?notify=0', 'one'
      assert_response :created
      assert_nil Thread.current[:redmine_extended_api_suppress_notifications]

      put_page '/extended_api/projects/ecookbook/wiki/Then_loud.json', 'two'
      assert_response :created
      assert_operator wiki_mails('wiki_content_added'), :>, 0
    end
  end

  # The flag is an /extended_api option, as for issues: the core route keeps core's behaviour.
  def test_the_core_route_ignores_notify_false
    with_settings notified_events: %w(wiki_content_added) do
      put_page '/projects/ecookbook/wiki/Core_route.json?notify=false', 'core'
      assert_response :created
      assert_operator wiki_mails('wiki_content_added'), :>, 0
    end
  end

  # An import attaches its pictures with the page (wiki_page[uploads]); that keeps working.
  def test_notify_false_page_keeps_its_uploads
    set_tmp_attachments_directory
    token = json_upload_token
    with_settings notified_events: %w(wiki_content_added) do
      put '/extended_api/projects/ecookbook/wiki/With_picture.json?notify=false',
          params: {wiki_page: {text: '<p><img src="pic.png"></p>',
                               uploads: [{token: token, filename: 'pic.png', content_type: 'image/png'}]}},
          headers: credentials('jsmith')
      assert_response :created
      assert_equal ['pic.png'], WikiPage.find_by(title: 'With_picture').attachments.map(&:filename)
      assert_equal 0, wiki_mails('wiki_content_added')
    end
  end

  private

  def json_upload_token
    post '/uploads.json?filename=pic.png', params: 'PNG', headers: {'CONTENT_TYPE' => 'application/octet-stream'}.merge(credentials('jsmith'))
    assert_response :created
    JSON.parse(response.body)['upload']['token']
  end
end

# frozen_string_literal: true

require File.expand_path('../../../../test/test_helper', __dir__)

# SPR-540: attachments a browser would render as a document (SVG, HTML, XML) are downloaded
# as application/octet-stream; passive types keep their own. The stored file is untouched.
#
# Fixtures used: issue 1 of project 1 (ecookbook, public); jsmith (2) is a Manager there.
class SprintlyAttachmentDownloadsTest < Redmine::ApiTest::Base
  SVG = %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(document.domain)</script></svg>)

  def setup
    super
    set_tmp_attachments_directory
  end

  def attach(filename, content_type, bytes = SVG)
    Attachment.create!(container: Issue.find(1), file: bytes, filename: filename,
                       content_type: content_type, author: User.find(2))
  end

  def download(attachment)
    get "/attachments/download/#{attachment.id}/#{attachment.filename}", headers: credentials('jsmith')
    assert_response :success
  end

  def content_type
    response.media_type
  end

  def test_an_svg_is_downloaded_as_opaque_bytes
    att = attach('x.svg', 'image/svg+xml')
    download(att)

    assert_equal 'application/octet-stream', content_type
    assert_match(/\Aattachment;/, response.headers['Content-Disposition'])
    assert_equal SVG, response.body
    # The stored type is not rewritten: the API still reports what was uploaded.
    assert_equal 'image/svg+xml', att.reload.content_type
  end

  def test_html_and_xml_are_downloaded_as_opaque_bytes_whatever_their_spelling
    [
      ['page.html', 'text/html'],
      ['page.htm', 'TEXT/HTML; charset=utf-8'],
      ['page.xhtml', 'application/xhtml+xml'],
      ['data.xml', 'application/xml'],
      ['data.xml', 'text/xml'],
      ['feed.rss', 'application/rss+xml'],
      ['page.mht', 'multipart/related']
    ].each do |filename, type|
      download(attach(filename, type))
      assert_equal 'application/octet-stream', content_type, "#{filename} as #{type}"
    end
  end

  def test_a_file_without_a_stored_type_is_judged_by_the_type_redmine_detects_from_its_name
    att = attach('page.html', '')
    assert_equal 'text/html', att.reload.content_type # Redmine fills it from the name

    att.update_column(:content_type, '')
    download(att)
    assert_equal 'application/octet-stream', content_type
  end

  def test_passive_types_keep_their_own
    [
      ['a.png', 'image/png'],
      ['a.jpg', 'image/jpeg'],
      ['a.pdf', 'application/pdf'],
      ['a.txt', 'text/plain'],
      ['a.json', 'application/json'],
      ['a.mp4', 'video/mp4']
    ].each do |filename, type|
      download(attach(filename, type, 'bytes'))
      assert_equal type, content_type, filename
    end
  end

  def test_detects_active_types
    active = RedmineExtendedApi::Sprintly::AttachmentDownloads
    assert active.active?('image/svg+xml')
    assert active.active?(' Image/SVG+XML ; charset=utf-8')
    assert active.active?('audio/x+xml')
    refute active.active?('image/png')
    refute active.active?('application/xml-dtd')
    refute active.active?(nil)
  end
end

# frozen_string_literal: true

# SPR-529: mail about a comment on a wiki page — to the people it mentions, and to the page's
# watchers when the tenant mails wiki changes (see SprintlyWikiComment).
class SprintlyWikiMailer < Mailer
  # `mentioned`: the mail says "mentioned you" rather than "commented".
  def wiki_comment_added(user, comment, mentioned)
    page = comment.page
    redmine_headers 'Project' => page.project.identifier, 'Wiki-Page-Id' => page.id
    @author = comment.author
    @user = user
    @comment = comment
    @mentioned = mentioned
    @page_title = page.pretty_title
    @page_url = url_for(controller: 'wiki', action: 'show', project_id: page.project, id: page.title)
    references page
    mail(
      to: user,
      subject: "[#{page.project.name}] #{l(:mail_subject_sprintly_wiki_comment_added, id: @page_title)}"
    )
  end
end

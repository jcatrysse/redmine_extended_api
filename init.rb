# frozen_string_literal: true
require_relative 'lib/redmine_extended_api'
require_relative 'lib/redmine_extended_api/custom_fields/attribute_policy'
require_relative 'lib/redmine_extended_api/mail_suppression_interceptor'
require_relative 'lib/redmine_extended_api/patches/api_helpers'
require_relative 'lib/redmine_extended_api/patches/attachments_controller_patch'
require_relative 'lib/redmine_extended_api/patches/attachment_patch'
require_relative 'lib/redmine_extended_api/patches/custom_fields_controller_patch'
require_relative 'lib/redmine_extended_api/patches/enumerations_controller_patch'
require_relative 'lib/redmine_extended_api/patches/issue_patch'
require_relative 'lib/redmine_extended_api/patches/issue_relations_controller_patch'
require_relative 'lib/redmine_extended_api/patches/issue_statuses_controller_patch'
require_relative 'lib/redmine_extended_api/patches/issues_controller_patch'
require_relative 'lib/redmine_extended_api/patches/journal_patch'
require_relative 'lib/redmine_extended_api/patches/notification_suppression_patch'
require_relative 'lib/redmine_extended_api/patches/roles_controller_patch'
require_relative 'lib/redmine_extended_api/patches/settings_controller_patch'
require_relative 'lib/redmine_extended_api/patches/trackers_controller_patch'
require_relative 'lib/redmine_extended_api/patches/webhook_patch'
require_relative 'lib/redmine_extended_api/patches/wiki_page_labels_patch'
require_relative 'lib/redmine_extended_api/patches/wiki_controller_patch'
require_relative 'lib/redmine_extended_api/proxy_app'
require_relative 'lib/redmine_extended_api/sprintly/permissions'
require_relative 'lib/redmine_extended_api/sprintly/store'
require_relative 'lib/redmine_extended_api/sprintly/access'
require_relative 'lib/redmine_extended_api/sprintly/model_patches'
require_relative 'lib/redmine_extended_api/sprintly/controller_patches'
require_relative 'lib/redmine_extended_api/sprintly/wiki_social'
require_relative 'lib/redmine_extended_api/sprintly/wiki_blocks'
require_relative 'lib/redmine_extended_api/sprintly/wiki_labels'

Redmine::Plugin.register :redmine_extended_api do
  name 'Redmine Extended API'
  author 'Jan Catrysse'
  description 'This plugin extends the default Redmine API by adding new endpoints and enabling write operations where only read access was previously available.'
  url 'https://github.com/jcatrysse/redmine_extended_api'
  version '0.1.0'
  requires_redmine version_or_higher: '5.1'

  # SPR-383: storage of the Sprintly role model (see Sprintly::Store). No settings page.
  # SPR-530: labels of wiki pages (see Sprintly::WikiLabels).
  settings default: { 'sprintly_access' => '', 'sprintly_wiki_labels' => '' }

  # SPR-383: every SPA permission is a Redmine permission, so roles store them and
  # `allowed_to?` answers for them (see Sprintly::Permissions).
  RedmineExtendedApi::Sprintly::Permissions::APP_PERMISSIONS.each do |app_id|
    permission RedmineExtendedApi::Sprintly::Permissions.symbol_for(app_id), {}
  end
end

Attachment.prepend RedmineExtendedApi::Patches::AttachmentPatch
AttachmentsController.prepend RedmineExtendedApi::Patches::AttachmentsControllerPatch
CustomFieldsController.prepend RedmineExtendedApi::Patches::CustomFieldsControllerPatch
EnumerationsController.prepend RedmineExtendedApi::Patches::EnumerationsControllerPatch
Issue.prepend RedmineExtendedApi::Patches::IssuePatch
Issue.include RedmineExtendedApi::Patches::NotificationSuppressionPatch
IssueRelationsController.prepend RedmineExtendedApi::Patches::IssueRelationsControllerPatch
IssuesController.prepend RedmineExtendedApi::Patches::IssuesControllerPatch
IssueStatusesController.prepend RedmineExtendedApi::Patches::IssueStatusesControllerPatch
Journal.include RedmineExtendedApi::Patches::NotificationSuppressionPatch
Journal.include RedmineExtendedApi::Patches::JournalPatch
ActionMailer::Base.register_interceptor(RedmineExtendedApi::MailSuppressionInterceptor)
RolesController.prepend RedmineExtendedApi::Patches::RolesControllerPatch
SettingsController.prepend RedmineExtendedApi::Patches::SettingsControllerPatch
TrackersController.prepend RedmineExtendedApi::Patches::TrackersControllerPatch

# Webhooks are new in Redmine 7
Webhook.singleton_class.prepend RedmineExtendedApi::Patches::WebhookPatch if defined?(::Webhook)

# SPR-383: server-side enforcement of the Sprintly role model; inert until the tenant is imported.
Issue.prepend RedmineExtendedApi::Sprintly::ModelPatches::IssuePatch
User.prepend RedmineExtendedApi::Sprintly::ModelPatches::UserPatch
Member.include RedmineExtendedApi::Sprintly::ModelPatches::MemberPatch
Group.prepend RedmineExtendedApi::Sprintly::ModelPatches::GroupPatch
WatchersController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::WatchersControllerPatch
VersionsController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::VersionsControllerPatch
WikiController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::WikiControllerPatch
TimelogController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::TimelogControllerPatch
AttachmentsController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::AttachmentsControllerPatch
FilesController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::FilesControllerPatch

# SPR-529: comments under wiki pages (SprintlyWikiCommentsController) and SPA mentions in them
# and in the pages themselves.
WikiPage.include RedmineExtendedApi::Sprintly::WikiSocial::WikiPagePatch
WikiContent.prepend RedmineExtendedApi::Sprintly::WikiSocial::MentionScan

# SPR-530: labels of wiki pages (Sprintly::WikiLabels) are deleted with their page.
WikiPage.include RedmineExtendedApi::Patches::WikiPageLabelsPatch

# SPR-525: notify=false for wiki writes through /extended_api (bulk import)
WikiController.prepend RedmineExtendedApi::Patches::WikiControllerPatch
WikiContent.prepend RedmineExtendedApi::Patches::WikiContentNotificationPatch

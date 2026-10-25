# frozen_string_literal: true
require_relative 'lib/redmine_extended_api'
require_relative 'lib/redmine_extended_api/custom_fields/attribute_policy'
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
require_relative 'lib/redmine_extended_api/proxy_app'
require_relative 'lib/redmine_extended_api/sprintly/permissions'
require_relative 'lib/redmine_extended_api/sprintly/store'
require_relative 'lib/redmine_extended_api/sprintly/access'
require_relative 'lib/redmine_extended_api/sprintly/model_patches'
require_relative 'lib/redmine_extended_api/sprintly/controller_patches'

Redmine::Plugin.register :redmine_extended_api do
  name 'Redmine Extended API'
  author 'Jan Catrysse'
  description 'This plugin extends the default Redmine API by adding new endpoints and enabling write operations where only read access was previously available.'
  url 'https://github.com/jcatrysse/redmine_extended_api'
  version '0.1.0'
  requires_redmine version_or_higher: '5.0'

  # SPR-383: storage of the Sprintly role model (see Sprintly::Store). No settings page.
  settings default: { 'sprintly_access' => '' }

  # SPR-383: every SPA permission is a Redmine permission, so roles store them and
  # `allowed_to?` answers for them (see Sprintly::Permissions).
  RedmineExtendedApi::Sprintly::Permissions::APP_PERMISSIONS.each do |app_id|
    permission RedmineExtendedApi::Sprintly::Permissions.symbol_for(app_id), {}
  end
end

Attachment.include RedmineExtendedApi::Patches::AttachmentPatch
AttachmentsController.prepend RedmineExtendedApi::Patches::AttachmentsControllerPatch
CustomFieldsController.prepend RedmineExtendedApi::Patches::CustomFieldsControllerPatch
EnumerationsController.prepend RedmineExtendedApi::Patches::EnumerationsControllerPatch
Issue.include RedmineExtendedApi::Patches::IssuePatch
Issue.include RedmineExtendedApi::Patches::NotificationSuppressionPatch
IssueRelationsController.prepend RedmineExtendedApi::Patches::IssueRelationsControllerPatch
IssuesController.prepend RedmineExtendedApi::Patches::IssuesControllerPatch
IssueStatusesController.prepend RedmineExtendedApi::Patches::IssueStatusesControllerPatch
Journal.include RedmineExtendedApi::Patches::NotificationSuppressionPatch
Journal.include RedmineExtendedApi::Patches::JournalPatch
RolesController.prepend RedmineExtendedApi::Patches::RolesControllerPatch
SettingsController.prepend RedmineExtendedApi::Patches::SettingsControllerPatch
TrackersController.prepend RedmineExtendedApi::Patches::TrackersControllerPatch

# SPR-383: server-side enforcement of the Sprintly role model; inert until the tenant is imported.
Issue.prepend RedmineExtendedApi::Sprintly::ModelPatches::IssuePatch
User.prepend RedmineExtendedApi::Sprintly::ModelPatches::UserPatch
Member.include RedmineExtendedApi::Sprintly::ModelPatches::MemberPatch
Group.prepend RedmineExtendedApi::Sprintly::ModelPatches::GroupPatch
WatchersController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::WatchersControllerPatch
VersionsController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::VersionsControllerPatch
WikiController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::WikiControllerPatch
TimelogController.prepend RedmineExtendedApi::Sprintly::ControllerPatches::TimelogControllerPatch

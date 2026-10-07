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
require_relative 'lib/redmine_extended_api/patches/trackers_controller_patch'
require_relative 'lib/redmine_extended_api/patches/webhook_patch'
require_relative 'lib/redmine_extended_api/proxy_app'

Redmine::Plugin.register :redmine_extended_api do
  name 'Redmine Extended API'
  author 'Jan Catrysse'
  description 'This plugin extends the default Redmine API by adding new endpoints and enabling write operations where only read access was previously available.'
  url 'https://github.com/jcatrysse/redmine_extended_api'
  version '0.1.0'
  requires_redmine version_or_higher: '5.0'
end

Attachment.prepend RedmineExtendedApi::Patches::AttachmentPatch
AttachmentsController.prepend RedmineExtendedApi::Patches::AttachmentsControllerPatch
CustomFieldsController.prepend RedmineExtendedApi::Patches::CustomFieldsControllerPatch
EnumerationsController.prepend RedmineExtendedApi::Patches::EnumerationsControllerPatch
Issue.prepend RedmineExtendedApi::Patches::IssuePatch
Issue.prepend RedmineExtendedApi::Patches::NotificationSuppressionPatch
IssueRelationsController.prepend RedmineExtendedApi::Patches::IssueRelationsControllerPatch
IssuesController.prepend RedmineExtendedApi::Patches::IssuesControllerPatch
IssueStatusesController.prepend RedmineExtendedApi::Patches::IssueStatusesControllerPatch
Journal.prepend RedmineExtendedApi::Patches::NotificationSuppressionPatch
Journal.include RedmineExtendedApi::Patches::JournalPatch
ActionMailer::Base.register_interceptor(RedmineExtendedApi::MailSuppressionInterceptor)
RolesController.prepend RedmineExtendedApi::Patches::RolesControllerPatch
TrackersController.prepend RedmineExtendedApi::Patches::TrackersControllerPatch
Webhook.singleton_class.prepend RedmineExtendedApi::Patches::WebhookPatch

# frozen_string_literal: true
require_relative 'lib/redmine_extended_api'
require_relative 'lib/redmine_extended_api/proxy_app'
require_relative 'lib/redmine_extended_api/custom_fields/attribute_policy'
require_relative 'lib/redmine_extended_api/patches/api_helpers'
require_relative 'lib/redmine_extended_api/patches/custom_fields_controller_patch'
require_relative 'lib/redmine_extended_api/patches/enumerations_controller_patch'
require_relative 'lib/redmine_extended_api/patches/issue_statuses_controller_patch'
require_relative 'lib/redmine_extended_api/patches/trackers_controller_patch'
require_relative 'lib/redmine_extended_api/patches/roles_controller_patch'

Redmine::Plugin.register :redmine_extended_api do
  name 'Redmine Extended API'
  author 'Jan Catrysse'
  description 'This plugin extends the default Redmine API by adding new endpoints and enabling write operations where only read access was previously available.'
  url 'https://github.com/jcatrysse/redmine_extended_api'
  version '0.0.2'
  requires_redmine version_or_higher: '5.0'
end

RolesController.prepend RedmineExtendedApi::Patches::RolesControllerPatch
IssueStatusesController.prepend RedmineExtendedApi::Patches::IssueStatusesControllerPatch
TrackersController.prepend RedmineExtendedApi::Patches::TrackersControllerPatch
EnumerationsController.prepend RedmineExtendedApi::Patches::EnumerationsControllerPatch
CustomFieldsController.prepend RedmineExtendedApi::Patches::CustomFieldsControllerPatch

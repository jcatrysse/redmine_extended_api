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
require_relative 'lib/redmine_extended_api/patches/trackers_controller_patch'
require_relative 'lib/redmine_extended_api/proxy_app'
require_relative 'lib/geo_reporter_diagnostic'
require_relative 'lib/geo_stats/query_aggregator'

# Register the geo_aggregate Liquid tag after ALL plugins have loaded.
# init.rb runs inside Redmine's own to_prepare block (PluginLoader calls
# run_initializer for every plugin sequentially). Nesting another to_prepare
# here defers to the next cycle — which never arrives in production.
# The after_plugins_loaded hook fires at the end of the same to_prepare
# execution, after every plugin's init.rb (including Reporter's) has run.
class GeoStatsLiquidTagLoader < Redmine::Hook::Listener
  def after_plugins_loaded(context = {})
    return unless defined?(Liquid::Tag)

    require_relative 'lib/geo_stats/liquid_aggregate_tag'
    Liquid::Template.register_tag('geo_aggregate', GeoStats::LiquidAggregateTag)

    begin
      # Object.const_get triggers Zeitwerk autoload in development; in production
      # all classes are already loaded. NameError = Reporter not installed.
      klass = Object.const_get('IssueListReportTemplate')
      require_relative 'lib/geo_reporter_list_patch'
      klass.prepend(GeoReporterListPatch) unless klass.ancestors.include?(GeoReporterListPatch)
      Rails.logger.info('[geo_stats] GeoReporterListPatch applied to IssueListReportTemplate')
    rescue NameError
      nil
    rescue => e
      Rails.logger.warn("[geo_stats] IssueListReportTemplate patch failed: #{e.message}")
    end

    begin
      ctrl = Object.const_get('ReportTemplatesController')
      require_relative 'lib/reporter_report_content_patch'
      ctrl.prepend(ReporterReportContentPatch) unless ctrl.ancestors.include?(ReporterReportContentPatch)
      Rails.logger.info('[geo_stats] ReporterReportContentPatch applied to ReportTemplatesController')
    rescue NameError
      nil
    rescue => e
      Rails.logger.warn("[geo_stats] ReportTemplatesController patch failed: #{e.message}")
    end
  end
end

Redmine::Plugin.register :redmine_extended_api do
  name 'Redmine Extended API'
  author 'Jan Catrysse'
  description 'This plugin extends the default Redmine API by adding new endpoints and enabling write operations where only read access was previously available.'
  url 'https://github.com/jcatrysse/redmine_extended_api'
  version '0.1.0'
  requires_redmine version_or_higher: '5.0'
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
TrackersController.prepend RedmineExtendedApi::Patches::TrackersControllerPatch

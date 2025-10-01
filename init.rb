# frozen_string_literal: true
require_relative 'lib/redmine_extended_api'

Redmine::Plugin.register :redmine_extended_api do
  name 'Redmine Extended API'
  author 'Jan Catrysse'
  description 'This plugin extends the default Redmine API by adding new endpoints and enabling write operations where only read access was previously available.'
  url 'https://github.com/jcatrysse/redmine_extended_api'
  version '0.0.1'
  requires_redmine version_or_higher: '5.0'
end

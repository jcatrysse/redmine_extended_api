# frozen_string_literal: true

require_relative 'redmine_extended_api/proxy_app'

module RedmineExtendedApi
  API_PREFIX = '/extended_api'

  class << self
    def proxy_app
      @proxy_app ||= RedmineExtendedApi::ProxyApp.new
    end
  end
end

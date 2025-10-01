# frozen_string_literal: true

require 'json'
require 'rack/request'
require 'active_support/core_ext/string/inflections'

module RedmineExtendedApi
  class ProxyApp
    ROUTE_ENV_KEYS = %w[
      action_dispatch.request.parameters
      action_dispatch.request.path_parameters
      action_dispatch.request.query_parameters
      action_dispatch.request.request_parameters
      action_dispatch.request.formats
      action_dispatch.request.content_type
      action_dispatch.request.filtered_parameters
    ].freeze

    API_FORMATS = %w[json xml].freeze

    def call(env)
      rewritten_env = rewrite_env(env)
      request = build_request(rewritten_env)

      return Rails.application.call(rewritten_env) if api_request?(request)

      not_found_response
    end

    private

    def build_request(env)
      if defined?(ActionDispatch::Request)
        ActionDispatch::Request.new(env)
      else
        Rack::Request.new(env)
      end
    end

    def api_request?(request)
      route_params = recognize_route(request)
      return false unless route_params

      return false unless api_format?(route_params)

      controller = controller_for_route(route_params[:controller])
      return false unless controller

      accepts_api_auth?(controller, route_params[:action])
    end

    def api_format?(route_params)
      format = route_params[:format] || route_params['format']
      API_FORMATS.include?(format)
    end

    def recognize_route(request)
      Rails.application.routes.recognize_path(
        request.path,
        method: request.request_method
      )
    rescue StandardError
      nil
    end

    def controller_for_route(controller_path)
      return nil if controller_path.nil? || controller_path.empty?

      "#{controller_path}_controller".camelize.safe_constantize
    end

    def accepts_api_auth?(controller, action)
      return false unless action

      if controller.respond_to?(:accept_api_auth?)
        controller.accept_api_auth?(action)
      elsif controller.respond_to?(:accept_api_auth_actions)
        controller.accept_api_auth_actions.include?(action.to_sym)
      else
        false
      end
    end

    def not_found_response
      body = { error: 'Not a REST API endpoint' }.to_json
      [
        404,
        { 'Content-Type' => 'application/json; charset=utf-8' },
        [body]
      ]
    end

    def rewrite_env(env)
      env = env.dup

      original_script_name = env['SCRIPT_NAME'] || ''
      original_path_info = env['PATH_INFO'] || ''
      query_string = env['QUERY_STRING'] || ''

      new_script_name = remove_proxy_prefix_from(original_script_name)
      new_path_info = normalize_path(strip_proxy_prefix_from(original_path_info))

      request_path = build_request_path(new_script_name, new_path_info)
      full_path = build_full_path(request_path, query_string)

      env['redmine_extended_api.original_script_name'] = original_script_name
      env['redmine_extended_api.original_path_info'] = original_path_info

      env['SCRIPT_NAME'] = new_script_name
      env['PATH_INFO'] = new_path_info
      env['RAW_PATH_INFO'] = new_path_info
      env['REQUEST_PATH'] = request_path
      env['REQUEST_URI'] = full_path
      env['ORIGINAL_FULLPATH'] = full_path
      env['action_dispatch.original_path'] = request_path
      env['action_dispatch.original_fullpath'] = full_path

      ROUTE_ENV_KEYS.each { |key| env.delete(key) }
      env.delete('action_dispatch.routes')
      env.delete('rack.request.query_string')
      env.delete('rack.request.query_hash')
      env.delete('rack.request.form_hash')
      env.delete('rack.request.form_vars')

      env
    end

    def remove_proxy_prefix_from(script_name)
      return '' if script_name.nil? || script_name.empty?

      cleaned = script_name.sub(%r{#{Regexp.escape(RedmineExtendedApi::API_PREFIX)}\z}, '')
      cleaned.empty? ? '' : cleaned
    end

    def build_request_path(script_name, path_info)
      combined = "#{script_name}#{path_info}"
      combined.empty? ? '/' : combined
    end

    def build_full_path(request_path, query_string)
      return request_path if query_string.nil? || query_string.empty?

      "#{request_path}?#{query_string}"
    end

    def strip_proxy_prefix_from(path)
      return '' if path.nil? || path.empty?

      path.sub(%r{\A#{Regexp.escape(RedmineExtendedApi::API_PREFIX)}}, '')
    end

    def normalize_path(path)
      path.nil? || path.empty? ? '/' : path
    end
  end
end

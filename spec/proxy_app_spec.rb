# frozen_string_literal: true

require 'json'
require_relative 'spec_helper'

RSpec.describe RedmineExtendedApi::ProxyApp do
  subject(:proxy_app) { described_class.new }

  before do
    stub_const('ActionController::RoutingError', Class.new(StandardError)) unless defined?(ActionController::RoutingError)
  end

  describe '#rewrite_env' do
    def rewrite_env(env)
      proxy_app.send(:rewrite_env, env)
    end

    it 'removes the API prefix when there is no relative URL root' do
      env = {
        'SCRIPT_NAME' => '/extended_api',
        'PATH_INFO' => '/issues.json',
        'QUERY_STRING' => 'key=123'
      }

      rewritten = rewrite_env(env)

      expect(rewritten['redmine_extended_api.original_script_name']).to eq('/extended_api')
      expect(rewritten['redmine_extended_api.original_path_info']).to eq('/issues.json')

      expect(rewritten['SCRIPT_NAME']).to eq('')
      expect(rewritten['PATH_INFO']).to eq('/issues.json')
      expect(rewritten['RAW_PATH_INFO']).to eq('/issues.json')
      expect(rewritten['REQUEST_PATH']).to eq('/issues.json')
      expect(rewritten['REQUEST_URI']).to eq('/issues.json?key=123')
      expect(rewritten['ORIGINAL_FULLPATH']).to eq('/issues.json?key=123')
      expect(rewritten['action_dispatch.original_path']).to eq('/issues.json')
      expect(rewritten['action_dispatch.original_fullpath']).to eq('/issues.json?key=123')
      expect(rewritten).not_to have_key('rack.request.query_string')
      expect(rewritten).not_to have_key('rack.request.query_hash')
      expect(rewritten).not_to have_key('rack.request.form_hash')
      expect(rewritten).not_to have_key('rack.request.form_vars')
    end

    it 'retains the relative URL root when present' do
      env = {
        'SCRIPT_NAME' => '/redmine/extended_api',
        'PATH_INFO' => '/issues.json',
        'QUERY_STRING' => 'key=123'
      }

      rewritten = rewrite_env(env)

      expect(rewritten['redmine_extended_api.original_script_name']).to eq('/redmine/extended_api')
      expect(rewritten['redmine_extended_api.original_path_info']).to eq('/issues.json')

      expect(rewritten['SCRIPT_NAME']).to eq('/redmine')
      expect(rewritten['PATH_INFO']).to eq('/issues.json')
      expect(rewritten['RAW_PATH_INFO']).to eq('/issues.json')
      expect(rewritten['REQUEST_PATH']).to eq('/redmine/issues.json')
      expect(rewritten['REQUEST_URI']).to eq('/redmine/issues.json?key=123')
      expect(rewritten['ORIGINAL_FULLPATH']).to eq('/redmine/issues.json?key=123')
      expect(rewritten['action_dispatch.original_path']).to eq('/redmine/issues.json')
      expect(rewritten['action_dispatch.original_fullpath']).to eq('/redmine/issues.json?key=123')
    end

    it 'removes the API prefix from PATH_INFO when it is duplicated there' do
      env = {
        'SCRIPT_NAME' => '',
        'PATH_INFO' => '/extended_api/issues.json',
        'QUERY_STRING' => 'key=123'
      }

      rewritten = rewrite_env(env)

      expect(rewritten['redmine_extended_api.original_path_info']).to eq('/extended_api/issues.json')

      expect(rewritten['SCRIPT_NAME']).to eq('')
      expect(rewritten['PATH_INFO']).to eq('/issues.json')
      expect(rewritten['RAW_PATH_INFO']).to eq('/issues.json')
      expect(rewritten['REQUEST_PATH']).to eq('/issues.json')
      expect(rewritten['REQUEST_URI']).to eq('/issues.json?key=123')
      expect(rewritten['ORIGINAL_FULLPATH']).to eq('/issues.json?key=123')
      expect(rewritten['action_dispatch.original_path']).to eq('/issues.json')
      expect(rewritten['action_dispatch.original_fullpath']).to eq('/issues.json?key=123')
    end

    it 'normalises an empty path to the root path' do
      env = {
        'SCRIPT_NAME' => '/extended_api',
        'PATH_INFO' => '',
        'QUERY_STRING' => ''
      }

      rewritten = rewrite_env(env)

      expect(rewritten['SCRIPT_NAME']).to eq('')
      expect(rewritten['PATH_INFO']).to eq('/')
      expect(rewritten['RAW_PATH_INFO']).to eq('/')
      expect(rewritten['REQUEST_PATH']).to eq('/')
      expect(rewritten['REQUEST_URI']).to eq('/')
      expect(rewritten['ORIGINAL_FULLPATH']).to eq('/')
      expect(rewritten['action_dispatch.original_path']).to eq('/')
      expect(rewritten['action_dispatch.original_fullpath']).to eq('/')
    end
  end

  describe '#call' do
    let(:env) { { 'PATH_INFO' => '/extended_api/issues.json' } }
    let(:rewritten_env) { { 'PATH_INFO' => '/issues.json' } }
    let(:request) { double('Request', path: '/issues.json', request_method: 'GET') }
    let(:routes) { double('Routes') }
    let(:rails_app) { double('RailsApp', routes: routes) }

    before do
      unless defined?(Rails)
        rails_module = Module.new do
          class << self
            attr_accessor :application
          end
        end

        stub_const('Rails', rails_module)
      end

      allow(proxy_app).to receive(:rewrite_env).with(env).and_return(rewritten_env)
      allow(proxy_app).to receive(:build_request).with(rewritten_env).and_return(request)
      Rails.application = rails_app
    end

    context 'when the target action accepts API authentication' do
      let(:route_params) { { controller: 'issues', action: 'index', format: 'json' } }
      let(:response) { [200, { 'Content-Type' => 'application/json' }, ['{}']] }

      before do
        stub_const('IssuesController', Class.new do
          def self.accept_api_auth?(action)
            action.to_sym == :index
          end
        end)

        allow(routes).to receive(:recognize_path).with('/issues.json', method: 'GET').and_return(route_params)
        allow(rails_app).to receive(:call).with(rewritten_env).and_return(response)
      end

      it 'proxies the request to Rails' do
        expect(proxy_app.call(env)).to eq(response)
      end
    end

    context 'when the request uses XML format' do
      let(:env) { { 'PATH_INFO' => '/extended_api/issues.xml' } }
      let(:rewritten_env) { { 'PATH_INFO' => '/issues.xml' } }
      let(:request) { double('Request', path: '/issues.xml', request_method: 'GET') }
      let(:route_params) { { controller: 'issues', action: 'index', format: 'xml' } }
      let(:response) { [200, { 'Content-Type' => 'application/xml' }, ['<issues/>']] }

      before do
        stub_const('IssuesController', Class.new do
          def self.accept_api_auth?(action)
            action.to_sym == :index
          end
        end)

        allow(proxy_app).to receive(:rewrite_env).with(env).and_return(rewritten_env)
        allow(proxy_app).to receive(:build_request).with(rewritten_env).and_return(request)
        allow(routes).to receive(:recognize_path).with('/issues.xml', method: 'GET').and_return(route_params)
        allow(rails_app).to receive(:call).with(rewritten_env).and_return(response)
      end

      it 'proxies the request to Rails' do
        expect(proxy_app.call(env)).to eq(response)
      end
    end

    context 'when the target action does not accept API authentication' do
      let(:route_params) { { controller: 'my', action: 'page', format: 'json' } }

      before do
        stub_const('MyController', Class.new do
          def self.accept_api_auth?(_action)
            false
          end
        end)

        allow(routes).to receive(:recognize_path).with('/issues.json', method: 'GET').and_return(route_params)
      end

      it 'returns 404 without proxying' do
        expect(rails_app).not_to receive(:call)

        status, headers, body = proxy_app.call(env)

        expect(status).to eq(404)
        expect(headers['Content-Type']).to eq('application/json; charset=utf-8')
        expect(JSON.parse(body.first)).to eq('error' => 'Not a REST API endpoint')
      end
    end

    context 'when the request omits an API format' do
      let(:env) { { 'PATH_INFO' => '/extended_api/issues' } }
      let(:rewritten_env) { { 'PATH_INFO' => '/issues' } }
      let(:request) { double('Request', path: '/issues', request_method: 'GET') }

      before do
        stub_const('IssuesController', Class.new do
          def self.accept_api_auth?(_action)
            true
          end
        end)

        allow(proxy_app).to receive(:rewrite_env).with(env).and_return(rewritten_env)
        allow(proxy_app).to receive(:build_request).with(rewritten_env).and_return(request)
        allow(routes).to receive(:recognize_path).with('/issues', method: 'GET').and_return({ controller: 'issues', action: 'index' })
      end

      it 'returns 404 without proxying' do
        expect(rails_app).not_to receive(:call)

        status, headers, body = proxy_app.call(env)

        expect(status).to eq(404)
        expect(headers['Content-Type']).to eq('application/json; charset=utf-8')
        expect(JSON.parse(body.first)).to eq('error' => 'Not a REST API endpoint')
      end
    end

    context 'when the route cannot be resolved' do
      before do
        allow(routes).to receive(:recognize_path).with('/issues.json', method: 'GET').and_raise(ActionController::RoutingError.new('not found'))
      end

      it 'returns 404' do
        expect(rails_app).not_to receive(:call)

        status, = proxy_app.call(env)
        expect(status).to eq(404)
      end
    end
  end
end

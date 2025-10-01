# frozen_string_literal: true

require 'action_dispatch'
require 'action_controller'
require 'action_controller/metal'
require 'action_controller/base'
require 'active_support/core_ext/string/inflections'
require 'set'
require_relative 'spec_helper'

RSpec.describe 'extended API routes' do
  let(:route_set) { ActionDispatch::Routing::RouteSet.new }

  before do
    unless defined?(Rails)
      rails_module = Module.new do
        class << self
          attr_accessor :application
        end
      end

      stub_const('Rails', rails_module)
    end

    rails_app = double('RailsApp', routes: route_set)
    Rails.application = rails_app

    base_controller = if defined?(ApplicationController)
                         ApplicationController
                       else
                         stub_const('ApplicationController', Class.new(ActionController::Base))
                       end

    base_controller.singleton_class.class_eval do
      define_method(:action_methods) do
        @action_methods ||= Set.new(%w[index show create update destroy])
      end

      define_method(:controller_path) do
        name.to_s
            .sub(/Controller$/, '')
            .gsub('::', '/')
            .underscore
      end

      define_method(:action_encoding_template) do |_action|
        nil
      end
    end

    %w[CustomFields Enumerations IssueStatuses Trackers].each do |name|
      const_name = "#{name}Controller"
      stub_const(const_name, Class.new(base_controller))
    end

    load File.expand_path('../config/routes.rb', __dir__)
  end

  it 'recognizes the custom fields show route with JSON format' do
    params = route_set.recognize_path('/custom_fields/7.json', method: :get)

    expect(params[:controller]).to eq('custom_fields')
    expect(params[:action]).to eq('show')
    expect(params[:id]).to eq('7')
    expect(params[:format]).to eq('json')
  end

  it 'recognizes the enumerations show route with XML format' do
    params = route_set.recognize_path('/enumerations/3.xml', method: :get)

    expect(params[:controller]).to eq('enumerations')
    expect(params[:action]).to eq('show')
    expect(params[:id]).to eq('3')
    expect(params[:format]).to eq('xml')
  end

  it 'recognizes the issue statuses show route' do
    params = route_set.recognize_path('/issue_statuses/2.json', method: :get)

    expect(params[:controller]).to eq('issue_statuses')
    expect(params[:action]).to eq('show')
    expect(params[:id]).to eq('2')
    expect(params[:format]).to eq('json')
  end

  it 'recognizes the trackers show route' do
    params = route_set.recognize_path('/trackers/11.json', method: :get)

    expect(params[:controller]).to eq('trackers')
    expect(params[:action]).to eq('show')
    expect(params[:id]).to eq('11')
    expect(params[:format]).to eq('json')
  end
end

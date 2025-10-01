# frozen_string_literal: true

require 'bundler/setup'
require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'

require_relative '../lib/redmine_extended_api'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  config.disable_monkey_patching!
end

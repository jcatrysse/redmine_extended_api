# frozen_string_literal: true

require 'bundler/setup'
require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'
require 'logger' # ActiveSupport 6.1 (Redmine 5.1) needs it before itself
require 'active_support'
require 'active_support/time'
require 'active_support/core_ext/object/blank'

require_relative '../lib/redmine_extended_api'

# How Redmine sends the notification of an Issue or Journal: before_save callbacks, then
# send_notification (after_create_commit), which does nothing when notify? is false.
module FakeNotifyingRecord
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def before_save(name)
      (@before_save_callbacks ||= []) << name
    end

    def before_save_callbacks
      @before_save_callbacks || []
    end
  end

  attr_writer :notify

  def notify?
    @notify != false
  end

  def save
    self.class.before_save_callbacks.each { |callback| send(callback) }
    send(:send_notification)
    true
  end
end

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

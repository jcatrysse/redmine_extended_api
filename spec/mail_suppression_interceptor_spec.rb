# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/redmine_extended_api/mail_suppression_interceptor'

RSpec.describe RedmineExtendedApi::MailSuppressionInterceptor do
  let(:message) { Struct.new(:perform_deliveries).new(true) }

  after { Thread.current[:redmine_extended_api_suppress_notifications] = nil }

  it 'drops mail delivered in a thread that suppresses notifications' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    described_class.delivering_email(message)

    expect(message.perform_deliveries).to be(false)
  end

  it 'leaves mail of other threads alone' do
    Thread.current[:redmine_extended_api_suppress_notifications] = true

    Thread.new { described_class.delivering_email(message) }.join

    expect(message.perform_deliveries).to be(true)
  end

  it 'leaves mail alone without suppression' do
    described_class.delivering_email(message)

    expect(message.perform_deliveries).to be(true)
  end
end

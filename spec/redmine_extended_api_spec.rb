# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe RedmineExtendedApi do
  describe '.proxy_app' do
    it 'returns a proxy app instance' do
      expect(described_class.proxy_app).to be_a(RedmineExtendedApi::ProxyApp)
    end

    it 'memoizes the proxy app instance' do
      expect(described_class.proxy_app).to equal(described_class.proxy_app)
    end
  end
end

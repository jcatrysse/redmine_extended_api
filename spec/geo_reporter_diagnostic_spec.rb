# frozen_string_literal: true

require 'tmpdir'
require 'tempfile'
require 'pathname'
require 'active_support'
require 'active_support/notifications'

# Define Rails stub before loading the diagnostic module, which evaluates
# Rails.root at load time when defining DIAG_LOG.
unless defined?(Rails)
  module Rails
    class << self
      attr_accessor :application
      attr_writer :logger

      def logger
        @logger ||= Logger.new(File::NULL)
      end

      def root
        @root ||= Pathname.new(Dir.tmpdir)
      end
    end
  end
end

require_relative 'spec_helper'
require_relative '../lib/geo_reporter_diagnostic'

RSpec.describe GeoReporterDiagnostic do
  let(:log_path) { Tempfile.new(['geo_diag', '.log']).path }

  before do
    stub_const('GeoReporterDiagnostic::DIAG_LOG', log_path)
  end

  after do
    File.delete(log_path) if File.exist?(log_path)
  end

  describe '.wrap_render' do
    it 'yields and returns the block result' do
      result = described_class.wrap_render { 42 }
      expect(result).to eq(42)
    end

    it 'yields and returns a complex block result' do
      data = { foo: 'bar' }
      result = described_class.wrap_render { data }
      expect(result).to eq(data)
    end

    it 'writes a timing entry to the log file' do
      described_class.wrap_render { :noop }
      content = File.read(log_path)
      expect(content).to match(/\[GEO_DIAG\].*Template render:.*ms,.*SQL queries fired/)
    end

    it 'unsubscribes from sql.active_record after the block completes' do
      described_class.wrap_render { :noop }

      queries_after = 0
      probe = ActiveSupport::Notifications.subscribe('sql.active_record') { queries_after += 1 }
      ActiveSupport::Notifications.instrument('sql.active_record', sql: 'SELECT 1') {}
      ActiveSupport::Notifications.unsubscribe(probe)

      content = File.read(log_path)
      expect(content).to match(/0 SQL queries fired/)
      expect(queries_after).to eq(1)
    end

    it 'unsubscribes even when the block raises an exception' do
      expect {
        described_class.wrap_render { raise RuntimeError, 'boom' }
      }.to raise_error(RuntimeError, 'boom')

      content = File.read(log_path)
      expect(content).to match(/\[GEO_DIAG\].*Template render:/)
    end

    it 'counts SQL queries fired inside the block' do
      described_class.wrap_render do
        ActiveSupport::Notifications.instrument('sql.active_record',
          sql: 'SELECT * FROM issues WHERE project_id = 1') {}
        ActiveSupport::Notifications.instrument('sql.active_record',
          sql: 'SELECT COUNT(*) FROM issues WHERE project_id = 1') {}
      end

      content = File.read(log_path)
      expect(content).to match(/2 SQL queries fired/)
    end

    it 'skips schema_migrations queries from the count' do
      described_class.wrap_render do
        ActiveSupport::Notifications.instrument('sql.active_record',
          sql: 'SELECT "schema_migrations"."version" FROM "schema_migrations"') {}
      end

      content = File.read(log_path)
      expect(content).to match(/0 SQL queries fired/)
    end

    it 'skips BEGIN and COMMIT from the count' do
      described_class.wrap_render do
        ActiveSupport::Notifications.instrument('sql.active_record', sql: 'BEGIN') {}
        ActiveSupport::Notifications.instrument('sql.active_record', sql: 'COMMIT') {}
      end

      content = File.read(log_path)
      expect(content).to match(/0 SQL queries fired/)
    end
  end

  describe '.log' do
    it 'writes a timestamped GEO_DIAG line to the diagnostic log file' do
      described_class.log('test message')
      content = File.read(log_path)
      expect(content).to match(/\[GEO_DIAG\] \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} test message/)
    end

    it 'appends multiple entries on separate lines' do
      described_class.log('first')
      described_class.log('second')
      content = File.read(log_path)
      expect(content).to include('first')
      expect(content).to include('second')
    end
  end
end

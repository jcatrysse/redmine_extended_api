# frozen_string_literal: true
# TEMPORARY DIAGNOSTIC — remove after double-run root cause is identified

module GeoReporterDiagnostic
  DIAG_LOG = Rails.root.join('log', 'geo_reporter_diagnostic.log').freeze

  def self.log(msg)
    ts   = Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N')
    line = "[GEO_DIAG] #{ts} #{msg}"
    Rails.logger.info(line)
    File.open(DIAG_LOG, 'a') { |f| f.puts(line) }
  end

  def self.wrap_render
    query_count = 0
    query_log   = []

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      sql   = event.payload[:sql].to_s
      next if sql =~ /\A\s*(SELECT\s+"schema_migrations|SHOW\s|SET\s|BEGIN|COMMIT|ROLLBACK)/i

      query_count += 1
      query_log << "  Q#{query_count} (#{event.duration.round(1)}ms): #{sql.gsub(/\s+/, ' ').strip[0..200]}"
    end

    t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = nil
    begin
      result = yield
    ensure
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveSupport::Notifications.unsubscribe(subscriber)
      elapsed = ((t1 - t0) * 1000).round(1)
      log "Template render: #{elapsed}ms, #{query_count} SQL queries fired"
      query_log.each { |q| log q }
    end
    result
  end
end

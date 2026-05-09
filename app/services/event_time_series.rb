class EventTimeSeries
  RANGES = {
    "24h" => { duration: 24.hours,  bucket: 1.hour,  label_format: "%H:00" },
    "7d"  => { duration: 7.days,    bucket: 1.day,   label_format: "%b %d" },
    "30d" => { duration: 30.days,   bucket: 1.day,   label_format: "%b %d" }
  }.freeze

  DEFAULT_RANGE = "24h".freeze

  def self.for_project(project, range: DEFAULT_RANGE, fingerprint: nil, environment: nil)
    new(project, range: range, fingerprint: fingerprint, environment: environment).to_h
  end

  def initialize(project, range:, fingerprint: nil, environment: nil)
    @project     = project
    @config      = RANGES[range.to_s] || RANGES[DEFAULT_RANGE]
    @fingerprint = fingerprint.presence
    @environment = environment.presence
    @now         = Time.current
    @bucket_count = (@config[:duration].to_i / @config[:bucket].to_i)
    @start       = bucket_start(@now) - @config[:bucket] * (@bucket_count - 1)
  end

  def to_h
    buckets = build_empty_buckets
    fill(buckets, fetch_counts)
    {
      range:   @config.slice(:duration, :bucket),
      buckets: buckets.map { |b|
        {
          t:        b[:start].iso8601,
          label:    b[:start].strftime(@config[:label_format]),
          count:    b[:count],
          by_level: b[:by_level]
        }
      },
      total: buckets.sum { |b| b[:count] }
    }
  end

  private

  def build_empty_buckets
    step = @config[:bucket]
    (0...@bucket_count).map do |i|
      { start: @start + step * i, count: 0, by_level: Hash.new(0) }
    end
  end

  def bucket_start(time)
    @config[:bucket] == 1.hour ? time.beginning_of_hour : time.beginning_of_day
  end

  def fetch_counts
    bucket_unit = @config[:bucket] == 1.hour ? "hour" : "day"
    EventRepository.time_series_counts(
      project:     @project,
      start_time:  @start,
      end_time:    @now,
      fingerprint: @fingerprint,
      environment: @environment,
      bucket_unit: bucket_unit
    )
  end

  def fill(buckets, rows)
    index = buckets.index_by { |b| b[:start].utc.to_i }
    rows.each do |bucket_at, level, c|
      key = bucket_at.to_i
      entry = index[key]
      next unless entry
      entry[:count] += c
      entry[:by_level][Event.levels.key(level) || level.to_s] += c
    end
  end
end

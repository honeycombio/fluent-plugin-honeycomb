require 'date'
require 'helper'

class HoneycombOutput < Test::Unit::TestCase
  attr_accessor :index_cmds, :index_command_counts

  def setup
    Fluent::Test.setup
    require 'fluent/plugin/out_honeycomb'
    @driver = nil
    log = Fluent::Engine.log
    log.out.logs.slice!(0, log.out.logs.length)
  end

  def driver(tag='test', conf='')
    @driver ||= Fluent::Test::BufferedOutputTestDriver.new(Fluent::HoneycombOutput, tag) {}.configure(conf)
  end

  def defaultconfig
    %{
      writekey bananarama
      dataset testdataset
    }
  end

  def sample
    {"status" => 200,"path" => "/docs/","latency_ms" => 13.1,"cached" => false}
  end

  def stub_hny(url="https://api.honeycomb.io/1/batch/testdataset")
    body = JSON.dump([{"status" => 202}])
    stub_request(:post, url).
      to_return(:status => 200, :body => body).with do |req|
        @events = req.body.split("\n").map {|r| JSON.parse(r) }
    end
  end

  def send_helper(extra_opts, inputs, request_bodies)
    config = defaultconfig + "\n" + extra_opts
    driver('test', config)
    hny_request = stub_hny()
    inputs.each { |i| driver.emit(i) }
    driver.run
    assert_requested(hny_request)
    assert_equal request_bodies, @events
  end

  def test_configure
    config = %{
      api_host     https://api-alt.honeycomb.io
      writekey bananarama
      dataset  testdataset
    }
    instance = driver('test', config).instance

    assert_equal 'https://api-alt.honeycomb.io', instance.api_host
    assert_equal 'bananarama', instance.writekey
    assert_equal 'testdataset', instance.dataset
    assert_equal 512000, instance.buffer_chunk_limit
    assert_equal 1, instance.flush_interval
    assert_equal 30, instance.max_retry_wait
    assert_equal 17, instance.retry_limit
  end

  def test_configure_overrides
    config = %{
      api_host     https://api-alt.honeycomb.io
      writekey bananarama
      dataset  testdataset
      buffer_chunk_limit 1m
      flush_interval 22s
      max_retry_wait 1m
      retry_limit 30
    }
    instance = driver('test', config).instance
    assert_equal 1024 * 1024, instance.buffer_chunk_limit
    assert_equal 22, instance.flush_interval
    assert_equal 60, instance.max_retry_wait
    assert_equal 30, instance.retry_limit
  end

  def test_send_with_fluentd_tag_key
    extra_opts = "include_tag_key true"
    inputs = [{"a" => "b", "c" => 22}]
    request_bodies = [
        [
          {"data" => {"a" => "b", "c" => 22, "fluentd_tag" => "test"},
           "time"=>"2006-01-02T15:04:05+00:00", "samplerate" => 1}
        ]
    ]
    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_send_with_custom_fluentd_tag_key
    extra_opts = %{
      include_tag_key true
      tag_key my_custom_tag_key_name
    }
    inputs = [{"a" => "b", "c" => 22}]
    request_bodies = [
        [
          {"data" => {"a" => "b", "c" => 22, "my_custom_tag_key_name" => "test"},
           "time"=>"2006-01-02T15:04:05+00:00", "samplerate" => 1}
        ]
    ]
    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_batching
    inputs = [{"a" => "b", "c" => 22},
              {"q" => "r", "s" => "t"}]
    request_bodies = [
        [
          {"data" => {"a" => "b", "c" => 22}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"q" => "r", "s" => "t"}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
        ]
    ]
    send_helper("", inputs, request_bodies)
  end

  def test_non_hash_records_skipped
    driver('test', defaultconfig)
    hny_request = stub_hny()
    driver.emit('not_json')
    driver.run
    assert_not_requested(hny_request)
  end

  def test_retry_on_all
    driver('test', defaultconfig)
    stub_request(:post, "https://api.honeycomb.io/1/batch/testdataset").
      to_return(:status => 500)
    driver.emit({"a" => "b"})
    assert_raise Exception do
      driver.run
    end
  end

  def test_retry_on_some
    # Test plugin-internal retry handling of responses where some (but not
    # all) events were rejected. We do this by stubbing the response to be
    # [{status: 202}, {status: 429}, {status: 429}, ...],
    # rejecting all but the first event. We then send a batch of ten events and
    # make sure that each event is ultimately (after retrying) accepted exactly
    # once.
    @received_events = []
    driver('test', defaultconfig)
    responses = []
    (0..10).each do |i|
      body = [{status: 202}].concat([{status: 429}] * (10 - i))
      responses.push({status: 200, body: JSON.dump(body)})
    end
    stub_request(:post, "https://api.honeycomb.io/1/batch/testdataset").
      to_return(responses).with do |req|
        fields = JSON.parse(req.body)
        @received_events.push(fields[0])
      end

    submitted_events = (0..10).map { |i| {"key" => i} }
    submitted_events.each { |ev| driver.emit(ev) }
    driver.run
    assert_equal(submitted_events, @received_events.map{ |ev| ev["data"] })
  end

  def test_sample_rate
    hny_request = stub_hny()
    config = defaultconfig + %{
    sample_rate 2
    }
    driver('test', config)
    (1..10000).each { |i| driver.emit({"a" => i}) }
    driver.run
    assert_requested(hny_request)
    events_sent = @events[0].length
    assert 2500 < events_sent && events_sent < 7500
  end

  def test_sample_rate_when_1
    hny_request = stub_hny()
    config = defaultconfig + %{
    sample_rate 1
    }
    driver('test', config)
    (1..10000).each { |i| driver.emit({"a" => i}) }
    driver.run
    assert_requested(hny_request)
    assert_equal 10000, @events[0].length
  end

  def test_no_merging_by_default
    inputs = [{"a" => "b", "c" => { "d" => 22, "e" => "f"}}]
    request_bodies = [
        [
          {"data" => {"a" => "b", "c" => {"d" => 22, "e" => "f"}}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
        ]
    ]
    send_helper("", inputs, request_bodies)
  end

  def test_merging
    extra_opts = %{flatten_keys ["a"]}
    inputs = [{"a" => {"b" => "c"}},
              {"a" => {"b" => "c"}, "d" => {"e" => "f"}},
              {"a" => {"b" => "c", "g" => {"h" => "j"}}},
              {"a" => {"b" => [1, 2]}}]
    request_bodies = [
        [
          {"data" => {"a.b" => "c"}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"a.b" => "c", "d" => {"e" => "f"}}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"a.b" => "c", "a.g.h" => "j"}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"a.b" => [1, 2]}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
        ]
    ]
    send_helper(extra_opts, inputs, request_bodies)
  end
end

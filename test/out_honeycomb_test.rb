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

  def stub_hny()
    url_template = Addressable::Template.new "https://api.honeycomb.io:443/1/batch/{dataset}"
    body = JSON.dump([{"status" => 202}])
    events = Hash.new
    stub = stub_request(:post, url_template).
      to_return(:status => 200, :body => body).with do |req|
        dataset = url_template.extract(req.uri)["dataset"]
        events[dataset] = JSON.parse(req.body)
    end
    return stub, events
  end

  def send_helper(extra_opts, inputs, request_bodies)
    config = defaultconfig + "\n" + extra_opts
    driver('test', config)

    _, events = stub_hny()
    inputs.each { |i| driver.emit(i) }
    driver.run
    assert_equal request_bodies, events
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
    request_bodies = { "testdataset" =>
        [
          {"data" => {"a" => "b", "c" => 22, "fluentd_tag" => "test"},
           "time"=>"2006-01-02T15:04:05+00:00", "samplerate" => 1}
        ]
    }
    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_send_with_custom_fluentd_tag_key
    extra_opts = %{
      include_tag_key true
      tag_key my_custom_tag_key_name
    }
    inputs = [{"a" => "b", "c" => 22}]
    request_bodies = { "testdataset" =>
        [
          {"data" => {"a" => "b", "c" => 22, "my_custom_tag_key_name" => "test"},
           "time"=>"2006-01-02T15:04:05+00:00", "samplerate" => 1}
        ]
    }
    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_batching
    inputs = [{"a" => "b", "c" => 22},
              {"q" => "r", "s" => "t"}]
    request_bodies = { "testdataset" =>
        [
          {"data" => {"a" => "b", "c" => 22}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"q" => "r", "s" => "t"}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
        ]
    }
    send_helper("", inputs, request_bodies)
  end

  def test_non_hash_records_skipped
    driver('test', defaultconfig)
    hny_request, _ = stub_hny()
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
    num_tests = 10000
    sample_rate = 4

    rand_returns = (1..sample_rate).to_a * (num_tests.to_f / sample_rate).ceil

    # Stub out rand call inside HomecombOutput, return array of
    # all potential values in order (1, 2, 3, 4, 1 ....)
    Fluent::HoneycombOutput.any_instance.expects(:rand)
      .at_least(num_tests)
      .returns(*rand_returns)

    hny_request, events = stub_hny()
    config = defaultconfig + %{
    sample_rate #{sample_rate}
    }
    driver('test', config)
    (1..num_tests).each { |i| driver.emit({"a" => i}) }
    driver.run
    assert_requested(hny_request)
    events_sent = events["testdataset"].length
    assert events_sent == num_tests / sample_rate
  end

  def test_sample_rate_when_1
    hny_request, events = stub_hny()
    config = defaultconfig + %{
    sample_rate 1
    }
    driver('test', config)
    (1..10000).each { |i| driver.emit({"a" => i}) }
    driver.run
    assert_requested(hny_request)
    assert_equal 10000, events["testdataset"].length
  end

  def test_no_merging_by_default
    inputs = [{"a" => "b", "c" => { "d" => 22, "e" => "f"}}]
    request_bodies = { "testdataset" =>
        [
          {"data" => {"a" => "b", "c" => {"d" => 22, "e" => "f"}}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
        ]
    }
    send_helper("", inputs, request_bodies)
  end

  def test_merging
    extra_opts = %{flatten_keys ["a"]}
    inputs = [{"a" => {"b" => "c"}},
              {"a" => {"b" => "c"}, "d" => {"e" => "f"}},
              {"a" => {"b" => "c", "g" => {"h" => "j"}}},
              {"a" => {"b" => [1, 2]}}]
    request_bodies = { "testdataset" =>
        [
          {"data" => {"a.b" => "c"}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"a.b" => "c", "d" => {"e" => "f"}}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"a.b" => "c", "a.g.h" => "j"}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"a.b" => [1, 2]}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
        ]
    }
    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_dataset_from_key
    extra_opts = %{dataset_from_key ds}
    inputs = [{"ds" => "dataset0", "a" => 1},
              {"ds" => "dataset0", "a" => 2},
              {"ds" => "dataset1", "b" => 1},
              {"ds" => "dataset1", "b" => 2},
              {"c" => 1},
              {"c" => 2}]
    request_bodies = {
        "dataset0" => [
            {"data" => {"a" => 1}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
            {"data" => {"a" => 2}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"}
        ],
        "dataset1" => [
            {"data" => {"b" => 1}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
            {"data" => {"b" => 2}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"}
        ],
        "testdataset" => [
            {"data" => {"c" => 1}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"},
            {"data" => {"c" => 2}, "samplerate" => 1, "time"=>"2006-01-02T15:04:05+00:00"}
        ]
    }

    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_presampled_key
    extra_opts = %{presampled_key sample_rate}

    inputs = [
      {"a" => 1, "sample_rate" => 10},
      {"a" => 2, "sample_rate" => 4},
      {"a" => 3},
      {"a" => 4, "sample_rate" => 2},
      {"a" => 5},
    ]

    request_bodies = {"testdataset" => [
      {"data" => {"a" => 1}, "samplerate" => 10, "time" => "2006-01-02T15:04:05+00:00"},
      {"data" => {"a" => 2}, "samplerate" => 4, "time" => "2006-01-02T15:04:05+00:00"},
      {"data" => {"a" => 3}, "samplerate" => 1, "time" => "2006-01-02T15:04:05+00:00"},
      {"data" => {"a" => 4}, "samplerate" => 2, "time" => "2006-01-02T15:04:05+00:00"},
      {"data" => {"a" => 5}, "samplerate" => 1, "time" => "2006-01-02T15:04:05+00:00"},
    ]}

    send_helper(extra_opts, inputs, request_bodies)
  end
end

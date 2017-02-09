require 'date'
require 'helper'
#require 'test/unit'
#require 'fluent/test'
#require 'webmock/test_unit'

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

  def stub_hny(url="https://api.honeycomb.io/1/batch")
    body = JSON.dump({"testdataset" => [{"status": 202}]})
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
    assert_equal @events, request_bodies
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
  end

  def test_send_with_fluentd_tag_key
    extra_opts = "include_tag_key true"
    inputs = [{"a" => "b", "c" => 22}]
    request_bodies = [
      {
        "testdataset" => [
          {"data" => {"a" => "b", "c" => 22, "fluentd_tag" => "test"},
           "time"=>"2006-01-02T15:04:05+00:00", "samplerate" => 1}
        ]
      }
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
      {
        "testdataset" => [
          {"data" => {"a" => "b", "c" => 22, "my_custom_tag_key_name" => "test"},
           "time"=>"2006-01-02T15:04:05+00:00", "samplerate" => 1}
        ]
      }
    ]
    send_helper(extra_opts, inputs, request_bodies)
  end

  def test_batching
    inputs = [{"a" => "b", "c" => 22},
              {"q" => "r", "s" => "t"}]
    request_bodies = [
      {
        "testdataset" => [
          {"data" => {"a" => "b", "c" => 22}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
          {"data" => {"q" => "r", "s" => "t"}, "samplerate" => 1,
           "time"=>"2006-01-02T15:04:05+00:00"},
        ]
      }
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

  def test_retry
    driver('test', defaultconfig)
    stub_request(:post, "https://api.honeycomb.io/1/batch").
      to_return(:status => 500)
    driver.emit({"a" => "b"})
    assert_raise Exception do
      driver.run
    end
  end
end

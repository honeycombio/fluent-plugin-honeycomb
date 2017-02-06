require 'date'
require 'test/unit'
require 'fluent/test'
require 'webmock/test_unit'

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
    {"status":200,"path":"/docs/","latency_ms":13.1,"cached":false}
  end

  def stub_hny(url="https://api.honeycomb.io/1/events/testdataset")
    stub_request(:post, url).
      to_return(:status => 200, :body => 'OK').with do |req|
        @events = req.body.split("\n").map {|r| JSON.parse(r) }
    end
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

  def test_send
    driver('test', defaultconfig())
    hny_request = stub_hny()

    driver.emit(sample())
    driver.run
    assert_requested(hny_request)
  end

  def test_send_with_fluentd_tag_key
    config = defaultconfig + %{
      include_tag_key true
    }
    driver('test', config)
    hny_request = stub_hny()
    driver.emit(sample())
    driver.run
    assert_requested(hny_request)
    assert_equal "test", @events[0]["fluentd_tag"]
  end

  def test_send_with_custom_fluentd_tag_key
    config = defaultconfig + %{
      include_tag_key true
      tag_key my_custom_tag_key_name
    }
    driver('test', config)
    hny_request = stub_hny()
    driver.emit(sample())
    driver.run
    assert_requested(hny_request)
    assert_equal "test", @events[0]["my_custom_tag_key_name"]
  end

end

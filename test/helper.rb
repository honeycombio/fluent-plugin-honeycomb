require 'simplecov'
require 'timecop'
SimpleCov.start do
  add_filter do |src|
    !(src.filename =~ /^#{SimpleCov.root}\/lib/)
  end
end

require 'test/unit'
require 'fluent/test'
require "mocha/test_unit"

require 'webmock/test_unit'
WebMock.disable_net_connect!
Timecop.freeze(Time.utc(2006, 01, 02, 15, 04, 05))

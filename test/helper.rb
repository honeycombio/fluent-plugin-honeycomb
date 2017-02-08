require 'simplecov'
SimpleCov.start do
  add_filter do |src|
    !(src.filename =~ /^#{SimpleCov.root}\/lib/)
  end
end

require 'test/unit'
require 'fluent/test'

require 'webmock/test_unit'
WebMock.disable_net_connect!

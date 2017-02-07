require 'fluent/output'
require 'libhoney'

module Fluent
  class HoneycombOutput < BufferedOutput
    # First, register the plugin. NAME is the name of this plugin
    # and identifies the plugin in the configuration file.
    Fluent::Plugin.register_output('honeycomb', self)

    # config_param defines a parameter. You can refer a parameter via @path instance variable
    # Without :default, a parameter is required.
    config_param :writekey, :string
    config_param :dataset, :string
    config_param :sample_rate, :integer, :default => 1
    config_param :include_tag_key, :bool, :default => false
    config_param :tag_key, :string, :default => "fluentd_tag"
    config_param :api_host, :string, :default => "https://api.honeycomb.io"

    # This method is called before starting.
    # 'conf' is a Hash that includes configuration parameters.
    # If the configuration is invalid, raise Fluent::ConfigError.
    def configure(conf)
      super

      # You can also refer raw parameter via conf[name].
      @path = conf['path']
    end

    # This method is called when starting.
    # Open sockets or files here.
    def start
      super
      @client = Libhoney::Client.new(:writekey => @writekey,
                                     :dataset => @dataset,
                                     :sample_rate => @sample_rate,
                                     :api_host => @api_host)
    end

    # This method is called when shutting down.
    # Shutdown the thread and close sockets or files here.
    def shutdown
      super
      # Drain libhoney request queue before shutting down.
      @client.close(true)
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    # This method is called every flush interval. Write the buffer chunk
    # to files or databases here.
    # 'chunk' is a buffer chunk that includes multiple formatted
    # events. You can use 'data = chunk.read' to get all events and
    # 'chunk.open {|io| ... }' to get IO objects.
    #
    # NOTE! This method is called by internal thread, not Fluentd's main thread. So IO wait doesn't affect other plugins.
    def write(chunk)
      chunk.msgpack_each do |(tag, time, record)|
        if !record.is_a? Hash
          $log.debug "Skipping record #{record}"
          next
        end
        if @include_tag_key
          record[@tag_key] = tag
        end
        @client.send_now(record)
        $log.debug "Sent record #{record}"
      end
    end
  end
end

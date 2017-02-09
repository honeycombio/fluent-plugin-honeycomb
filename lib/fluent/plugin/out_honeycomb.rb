require 'json'
require 'http'
require 'fluent/output'

module Fluent
  class HoneycombOutput < BufferedOutput
    # First, register the plugin. NAME is the name of this plugin
    # and identifies the plugin in the configuration file.
    Fluent::Plugin.register_output('honeycomb', self)

    # config_param defines a parameter. You can refer a parameter via @path instance variable
    # Without :default, a parameter is required.
    config_param :writekey, :string, :secret => true
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
    end

    # This method is called when shutting down.
    # Shutdown the thread and close sockets or files here.
    def shutdown
      super
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
      batch = []
      chunk.msgpack_each do |(tag, time, record)|
        if !record.is_a? Hash
          log.debug "Skipping record #{record}"
          next
        end
        if @include_tag_key
          record[@tag_key] = tag
        end
        batch.push({
            "data" => record,
            "samplerate" => @sample_rate,
            "time" => Time.at(time).utc.to_datetime.rfc3339
        })
      end

      if batch.length == 0
        return
      end
      log.info "publishing #{batch.length} records"
      body = JSON.dump({ @dataset => batch })
      resp = HTTP.headers(
          "User-Agent" => "fluent-plugin-honeycomb",
          "Content-Type" => "application/json",
          "X-Honeycomb-Team" => @writekey)
          .post(URI.join(@api_host, "/1/batch"), {
              :body => body,
          })
      parse_response(resp)
    end

    def parse_response(resp)
      if resp.status != 200
        # Force retry
        raise Exception.new("Error sending batch: #{resp.status}, #{resp.body}")
      else
        begin
          results = JSON.parse(resp.body)
        rescue JSON::ParserError => e
          log.warn "Error parsing response as JSON: #{e}"
          return
        end
        successes = 0
        failures = []
        if !results.is_a? Array
          return
        end
        results.each { |r|
          if r["status"] == 202
            successes += 1
          else
            failures[r["status"]] += 1
          end
        }

        log.debug "Successfully published #{batch.length} records"
        if failures.size > 0
          log.warn "Errors publishing records: #{failures}"
        end
      end
    end
  end
end

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
    config_param :flatten_keys, :array, value_type: :string, :default => []
    config_param :dataset_from_key, :string, :default => ""

    # This method is called before starting.
    # 'conf' is a Hash that includes configuration parameters.
    # If the configuration is invalid, raise Fluent::ConfigError.
    def configure(conf)
      # Apply sane defaults. These override the poor fluentd defaults, but not
      # anything explicitly specified in the configuration.
      conf["buffer_chunk_limit"] ||= "500k"
      conf["flush_interval"] ||= "1s"
      conf["max_retry_wait"] ||= "30s"
      conf["retry_limit"] ||= 17
      super
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
      batches =  Hash.new{ |h, k| h[k] = [] }
      chunk.msgpack_each do |(tag, time, record)|
        if !record.is_a? Hash
          log.debug "Skipping record #{record}"
          next
        end
        if @sample_rate > 1 && rand(1..@sample_rate) == 1
          next
        end
        if @include_tag_key
          record[@tag_key] = tag
        end
        @flatten_keys.each do |k|
          next unless record[k].is_a?(Hash)
          record.merge!(flatten(record[k], k))
          record.delete(k)
        end

        if (@dataset_from_key != "" && record.has_key?(@dataset_from_key))
          dataset = record[@dataset_from_key]
          record.delete @dataset_from_key
        else
          dataset = @dataset
        end
        batch = batches[dataset]
        batch.push({
            "data" => record,
            "samplerate" => @sample_rate,
            "time" => Time.at(time).utc.to_datetime.rfc3339
        })
      end

      batches.each do |dataset, batch|
        publish_batch(dataset, batch, 0)
      end
    end

    def publish_batch(dataset, batch, retry_count)
      if batch.length == 0
        return
      end
      log.info "publishing #{batch.length} records to dataset #{dataset}"
      body = JSON.dump(batch)
      resp = HTTP.headers(
          "User-Agent" => "fluent-plugin-honeycomb",
          "Content-Type" => "application/json",
          "X-Honeycomb-Team" => @writekey)
          .post(URI.join(@api_host, "/1/batch/#{dataset}"), {
              :body => body,
          })
      failures = parse_response(batch, resp)
      if failures.size > 0 && retry_count < @retry_limit
        # sleep and retry with the set of failed events
        sleep 1
        publish_batch(dataset, failures, retry_count + 1)
      end
    end

    def parse_response(batch, resp)
      if resp.status != 200
        # Force retry
        log.error "Error sending batch: #{resp.status}, #{resp.body}"
        raise Exception.new("Error sending batch: #{resp.status}, #{resp.body}")
      end

      begin
        results = JSON.parse(resp.body)
      rescue JSON::ParserError => e
        log.warn "Error parsing response as JSON: #{e}"
        raise e
      end
      successes = 0
      failures = []
      if !results.is_a? Array
        log.warning "Unexpected response format: #{results}"
        raise Exception.new("Unexpected response format: #{resp.status}")
      end

      results.each_with_index do |result, idx|
        if !result.is_a? Hash
          log.warning "Unexpected status format in response: #{result}"
          next
        end

        if result["status"] == 202
          successes += 1
        else
          failures.push(batch[idx])
        end
      end

      if failures.size > 0
        log.warn "Errors publishing records: #{failures.size} failures out of #{successes + failures.size}"
      else
        log.debug "Successfully published #{successes} records"
      end
      return failures
    end

    def flatten(record, prefix)
      ret = {}
      if record.is_a? Hash
        record.each { |key, value|
          ret.merge! flatten(value, "#{prefix}.#{key.to_s}")
        }
      else
        return {prefix => record}
      end
      ret
    end
  end
end

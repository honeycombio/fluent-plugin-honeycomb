# fluent-plugin-honeycomb

[![OSS Lifecycle](https://img.shields.io/osslifecycle/honeycombio/fluent-plugin-honeycomb)](https://github.com/honeycombio/home/blob/main/honeycomb-oss-lifecycle-and-practices.md)

Send your logs to [Honeycomb](https://honeycomb.io). (For more information about using Honeycomb, see [our docs](https://honeycomb.io/docs/).)

## Getting started

1. Install this plugin with `gem install fluent-plugin-honeycomb`

2. Edit your `fluentd.conf` configuration file. A minimal configuration looks like this:

```
<match your_match>
  @type honeycomb
  writekey "YOUR_WRITEKEY"
  dataset "fluentd_test_dataset"
</match>
```

## Configuration

### Basic options

Parameter | Type | Required? | Description
| --- | --- | --- | --- |
| `writekey` | string | yes | Your Honeycomb write key. |
| `dataset` | string | yes | The name of the destination dataset in your Honeycomb account. |
| `sample_rate` | integer | no | Sample your event stream by sending 1 out of every N events. |
| `include_tag_key` | bool | no | Whether to include the Fluentd tag in the submitted event. |
| `tag_key` | string | no | If `include_tag_key` is `true`, the tag key name in the event (default: `fluentd_tag`).
| `flatten_keys` | array | no | Flatten nested JSON data under these keys into the top-level event.
| `dataset_from_key` | string | no | Look for this key in each event, and use its value as the destination dataset. If an event doesn't contain the key, it'll be sent to the dataset given by the `dataset` parameter.
| `presampled_key` | string | no | Look for this key in each event, and use its value as the sample rate for the record. If an event doesn't contain the key, the logic around `sample_rate` will be used (1 out of every N events will be sent instead). If an event's `presampled_key` value is not a positive integer, the value is discarded, and the event is sent to Honeycomb with a `samplerate` of 1 (the default), ignoring the `sample_rate` configuration option. |

### Buffering options

`fluent-plugin-honeycomb` supports the [standard configuration options](http://docs.fluentd.org/v0.12/articles/buffer-plugin-overview) for buffered output plugins.

## Development
I recommend using [rbenv](https://github.com/rbenv/rbenv) for development.

To set up Fluentd, run:

```
gem install fluentd
fluentd --setup ./fluent
```

Edit the configuration file at `./fluent/fluent.conf`, then run

```
fluentd -c ./fluent/fluent.conf -v
```

A note about naming: This gem must be named `fluent-plugin-xxx` in order to automatically be included in Fluentd's plugin list. See http://www.fluentd.org/faqs.

## Releasing a new version
Travis will automatically upload tagged releases to Rubygems. To release a new
version:

1. Update the value of `HONEYCOMB_PLUGIN_VERSION` in
   lib/plugin/out_honeycomb_version.rb`

2. Update `spec.version` in `fluent-plugin-honeycomb.gemspec`.

3. Run
    ```
    bump patch --tag   # Or bump minor --tag, etc.
    git push --follow-tags
    ```

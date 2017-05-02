require 'aws-sdk'

module Lita
  module Handlers
    class MeterSidekick < Handler

      METERCTL_BUCKET='6fusion-meter-dev'

      route(/meter latest/, :latest, help: { 'meter latest' => 'Latest meter installers' })



      def latest(response)
        begin
          s3 = Aws::S3::Client.new
          bucket = s3.list_objects_v2(bucket: METERCTL_BUCKET)
          coreos = bucket.contents.select{|entry| entry.key.match(%r|coreos/.+/install|)}
          stable = coreos
                     .reject{|entry| entry.match(/alpha|beta/)}
                     .sort{|a,b| Gem::Version.new(a) <=> Gem::Version.new(b) }
                     .first
                     .key
          beta = coreos
                   .select{|entry| entry.end_with?('beta')}
                   .sort{|a,b| Gem::Version.new(a) <=> Gem::Version.new(b) }
                   .first
                   .key

          # FIXME how do you get this from the SDK
          url_base = 'https://s3.amazonaws.com/6fusion-meter-dev/'
          response.reply "#{url_base}/#{stable}\n#{url_base}/#{beta}"
        rescue => e
          response.reply(render_template('exception', exception: e))
        end
      end

      Lita.register_handler(self)
    end
  end
end

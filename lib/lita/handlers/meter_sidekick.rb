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
                     .map{|e| e.key.split('/')[1]}
                     .reject{|entry| entry.match(/alpha|beta/)}
                     .sort{|a,b| Gem::Version.new(a) <=> Gem::Version.new(b) }
                     .first
          beta = coreos
                   .map{|e| e.key.split('/')[1]}
                   .select{|entry| entry.end_with?('beta')}
                   .sort{|a,b| Gem::Version.new(a) <=> Gem::Version.new(b) }
                   .first

          # FIXME how do you get this from the SDK
          url_base = 'https://s3.amazonaws.com/6fusion-meter-dev/coreos'
          response.reply "#{url_base}/#{stable}/install\n#{url_base}/#{beta}/install"
        rescue => e
          response.reply(render_template('exception', exception: e))
          log e.message
          log e.backtrace.join("\n")
        end
      end

      Lita.register_handler(self)
    end
  end
end

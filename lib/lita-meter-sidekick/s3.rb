require 'aws-sdk'

module LitaMeterSidekick
  module S3

    METERCTL_BUCKET='6fusion-meter-dev'

    def latest(response)
      s3 = Aws::S3::Client.new
      bucket = s3.list_objects_v2(bucket: METERCTL_BUCKET)
      coreos = bucket.contents.select{|entry| entry.key.match(%r|coreos/.+/install|)}
      stable = coreos
                 .map{|e| e.key.split('/')[1]}
                 .reject{|entry| entry.match(/alpha|beta/)}
                 .sort{|a,b| Gem::Version.new(b) <=> Gem::Version.new(a) }
                 .first
      beta = coreos
               .map{|e| e.key.split('/')[1]}
               .select{|entry| entry.end_with?('beta')}
               .sort{|a,b| Gem::Version.new(b) <=> Gem::Version.new(a) }
               .first

      # FIXME how do you get this from the SDK
      url_base = 'https://s3.amazonaws.com/6fusion-meter-dev/coreos'
      response.reply(render_template('installer_links',
                                     stable: "#{url_base}/#{stable}/install",
                                     beta: beta.match(/#{stable}-beta/) ? 'There is no beta release currently in the works' : "#{url_base}/#{beta}/install",
                                     alpha: "#{url_base}/alpha/install")

    end
  end
end

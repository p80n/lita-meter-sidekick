require 'aws-sdk'
require 'net/http'

module LitaMeterSidekick
  module S3

    METERCTL_BUCKET='6fusion-meter-dev'
    RESOURCES_BASE_URL='https://resources.6fusion.com/meter/coreos'

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
      s3_base_url = 'https://s3.amazonaws.com/6fusion-meter-dev/coreos'

      warning = resources_updated_for?(stable) ?
                  nil :
                  "*Warning:* resources.6fusion.com not updated with latest. Stable installer will not work."

      beta_link = beta.match(/#{stable}-beta/) ?
                    'There is no beta release currently in the works' :
                    "#{s3_base_url}/#{beta}/install"

      response.reply(render_template('installer_links',
                                     stable: "#{RESOURCES_BASE_URL}/#{stable}/install",
                                     beta:   beta_link,
                                     alpha:  "#{s3_base_url}/alpha/install",
                                     warning: warning ))

    end

    private
    def resources_updated_for?(version)
      url = URI.parse("#{RESOURCES_BASE_URL}/#{version}/meterctl")
      request = Net::HTTP.new(url.host, url.port)
      response = request.request_head(url.path)
      response.code == '404'
    end
  end
end

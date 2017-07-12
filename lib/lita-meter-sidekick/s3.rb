require 'aws-sdk'
require 'net/http'

module LitaMeterSidekick
  module S3

    METERCTL_BUCKET='6fusion-meter-dev'

    def latest(response)
      s3 = Aws::S3::Client.new
      s3_base_url = 'https://s3.amazonaws.com/6fusion-meter-dev/coreos'
      resources_base_url = 'https://resources.6fusion.com/meter/coreos'
      curl = 'curl -sSL'

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

      stable_installer = "#{resources_base_url}/#{stable}/install"

      warning = resources_updated_for?(stable_installer) ?
                  nil :
                  ":warning: resources.6fusion.com not updated with latest. Stable installer will not work. :warning:"

      stable_command = "#{curl} #{stable_installer} | sudo bash",
      # if stable is e.g., 0.11, and beta is 0.11-beta (i.e., no 11.1, no .12) there is no beta release underway
      beta_command = beta.match(/#{stable}-beta/) ? nil : "#{curl} #{s3_base_url}/#{beta}/install | sudo bash"

      response.reply(render_template('installer_links',
                                     stable: stable_command,
                                     beta:   beta_command,
                                     alpha:  "#{curl} #{s3_base_url}/alpha/install | sudo bash",
                                     warning: warning ))

    end

    private
    def resources_updated_for?(stable_installer)
      p stable_installer
      url = URI.parse(stable_installer.sub('install','meterctl'))
      request = Net::HTTP.new(url.host, url.port)
      response = request.request_head(url.path)
      p response
      p response.code
      response.code == '404'
    end
  end
end

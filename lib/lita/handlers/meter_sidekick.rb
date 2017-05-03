module Lita
  module Handlers
    class MeterSidekick < Handler
      include ::LitaMeterSidekick::S3

      begin
        route(/meter latest/, :latest, help: { 'meter latest' => 'Links to installers for latest version of the Meter' })

        route(/meter deployed/, :list_deployed_meters, help: { 'meter deployed' => 'List all discoverable instances of the Meter in EC2' })

        Lita.register_handler(self)

      rescue => e
        response.reply(render_template('exception', exception: e))
        log e.message
        log e.backtrace.join("\n")
      end
    end
  end
end

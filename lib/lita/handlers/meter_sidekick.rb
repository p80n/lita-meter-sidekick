module Lita
  module Handlers
    class MeterSidekick < Handler
      include ::LitaMeterSidekick::S3
      include ::LitaMeterSidekick::EC2

      begin

        route(/latest release/, :latest, help: { 'latest release' => 'Links to installers for latest version of the Meter' })
        route(/meter latest/,   :latest, help: { 'meter latest'   => 'Links to installers for latest version of the Meter' })

        route(/list instances/,    :list_instances,       help: { 'list instances' => 'List all discoverable instances in EC2' })
        route(/list meters/,       :list_deployed_meters, help: { 'list meters' => 'List all discoverable instances of the Meter in EC2' })
        route(/list my instances/, :list_user_instances,  help: { 'list instances' => 'List all discoverable instances in EC2' })

        Lita.register_handler(self)

      rescue => e
        response.reply(render_template('exception', exception: e))
        log e.message
        log e.backtrace.join("\n")
      end
    end
  end
end

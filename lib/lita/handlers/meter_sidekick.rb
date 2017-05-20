module Lita
  module Handlers
    class MeterSidekick < Handler
      include ::LitaMeterSidekick::S3
      include ::LitaMeterSidekick::EC2

      begin
#        name = robot

        route(/latest release/, :latest, help: { 'latest release' => 'Links to installers for latest version of the Meter' })
        route(/meter latest/,   :latest, help: { 'meter latest'   => 'Links to installers for latest version of the Meter' })

        route(/list instances/,    :list_instances,       help: { 'list instances' => 'List all discoverable instances in EC2' })
        route(/list meters/,       :list_deployed_meters, help: { 'list meters' => 'List all discoverable instances of the Meter' })
        route(/list my instances/, :list_user_instances,  help: { 'list my instances' => 'List all instances owned by messager' })
        route(/list instances (\w+)=(\w+)/, :list_filtered_instances, help: { 'list instance TAG=VALUE' => 'List instances, filtered by tag' })

        Lita.register_handler(self)

      rescue => e
        response.reply(render_template('exception', exception: e))
        log e.message
        log e.backtrace.join("\n")
      end
    end
  end
end

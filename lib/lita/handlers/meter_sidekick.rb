module Lita
  module Handlers
    class MeterSidekick < Handler
      include ::LitaMeterSidekick::S3
      include ::LitaMeterSidekick::EC2

      begin
        name = 'lita'
        Lita.configure{|config|
          name = config.robot.name }

        route(/latest release/, :latest, help: { "#{name}: latest release" => 'Links to installers for latest version of the Meter' })
        route(/meter latest/,   :latest, help: { "#{name}: meter latest"   => 'Links to installers for latest version of the Meter' })

        route(/meter deploy\s*(.*)/,
              :deploy_meter,
              help: { "#{name}: meter deploy [options]" =>
                      'Deploy a meter. Options can be instance type and/or volume size (XXgb). Defaults to m4.xlarge with 30GB of storage.'})
        # route(/deploy instance (.*)/,
        #       :deploy_instance,
        #       help: { "#{name}: deploy instance DEETS" =>
        #               'Deploy an instance, DEETS can be a region, instance type. Defaults to t2.xlarge'})

        route(/list instances (\w+)=(\w+)/, :list_filtered_instances, help: { "#{name}: list instances TAG=VALUE" => 'List instances, filtered by tag' })
        route(/list instances$/,    :list_instances,       help: { "#{name}: list instances" => 'List all instances in EC2' })
        route(/list meters/,        :list_deployed_meters, help:  { "#{name}: list meters" => 'List all instances of the Meter' })
        route(/list my instances/,  :list_user_instances,  help:  { "#{name}: list my instances" => 'List all instances owned by you' })

        Lita.register_handler(self)

      rescue => e
        log e.message
        log e.backtrace.join("\n")
      end
    end
  end
end

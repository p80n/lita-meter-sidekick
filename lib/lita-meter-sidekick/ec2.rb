require 'aws-sdk'

module LitaMeterSidekick
  module EC2

    def list_deployed_meters(response)
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        meter_instances = ec2.instances(filters: [{ name: 'tag:ApplicationRole', values:['6fusionMeter'] }])
        response.reply(render_template('instance_list', instances: meter_instances))
      end
    end

    def regions
      @regions ||= Clients.ec2.describe_regions.data.regions.map(&:region_name)
    end

  end
end

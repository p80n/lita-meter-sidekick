require 'aws-sdk'

module LitaMeterSidekick
  module EC2

    def list_deployed_meters(response)
      meter_instances = []
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        instances = ec2.instances(filters: [{ name: 'tag:ApplicationRole', values:['6fusionMeter'] }])
        meter_instances += instances
      end
      response.reply(render_template('instance_list', instances: meter_instances))
    end

    def regions
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

  end
end

require 'base64'
require 'net/http'
require 'yaml'

require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def deploy_instance(response)

      begin

        options = response.matches[0][0]
        az = availability_zone(options)

        response.reply("Deploying instance to #{az.chop}...")

        p YAML.load(render_template('ignition.yml', version: 'alpha')).to_json
        user_data = Base64.strict_encode64(YAML.load(render_template('ignition.yml', version: 'alpha')).to_json)

        ec2 = Aws::EC2::Resource.new(region: az.chop)
        instances = ec2.create_instances({ image_id: coreos_image_id(az.chop, response),
                                          min_count: 1,
                                          max_count: 1,
                                          key_name: ssh_key(az),
                                          security_group_ids: [security_group(az)],
                                          subnet_id: vpc(options),
                                          user_data: user_data,
                                          instance_type: instance_type(options),
                                          placement: { availability_zone: az },
                                        })

        # Wait for the instance to be created, running, and passed status checks
        ec2.client.wait_until(:instance_running, {instance_ids: [instances[0].id]}){|w|
          w.interval = 10
          w.max_attempts = 100
          response.reply("Waiting for instance #{instances[0].id} to spin up...") }

        response.reply("Tagging your instance")

        # Name the instance 'MyGroovyInstance' and give it the Group tag 'MyGroovyGroup'
        instances.batch_create_tags({ tags: [{ key: 'Name', value: '6fusion Meter' },
                                             { key: 'CostCenter', value: 'development' },
                                             { key: 'Owner', value: aws_user_for(response.user.mention_name) },
                                             { key: 'DeployedBy', value: 'lita' },
                                             { key: 'ApplicationRole', value: '6fusion-meter' }
                                            ]
                                    })

        resp = ec2.client.get_console_output({ instance_id: instances.first.id })

        response.reply("Instance ready: `ssh -i #{ssh_key(az)} core@#{instances.first.public_dns_name}`")

      # summary of meters you own
      # attached with kubeconfig

      rescue => e
        response.reply(render_template('exception', exception: e))
      end


    end

    ####################################################################################################
    # List operations
    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values: ['6fusionMeter'] }])
    end
    def list_user_instances(response)
      list_instances(response, [{ name: 'tag:Owner', values: [aws_user(response.user.mention_name)] }])
    end
    def list_filtered_instances(response)
      tag,value = response.matches[0][0..1]
      list_instances(response, [{ name: "tag:#{tag}", values: [value] }])
    end


    def list_instances(response, filters=nil)
      instances = Array.new
      # FIXME use bulk endpoint
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        instances += ec2.instances(filters: filters).entries
      end

      if instances.empty?
        response.reply("No matching instances found")
      else
        content = render_template('instance_list', instances: instances)
        case robot.config.robot.adapter
        when :slack then robot.chat_service.send_file(response.user, content: content, title: "EC2 Instances")
        else robot.send_message(response.user, content)
        end
      end
    end

    private
    def vpc(options)
      if md = options.match(/(vpc-\w+)/)
        md[1]
      else
        case availability_zone(options)
        when /us-east-1/ then 'vpc-08c18d6c'
        else nil
        end
      end
    end


    def security_group(az)
      client = Aws::EC2::Client.new(region: az.chop)
      groups = client
                 .describe_security_groups
                 .security_groups
                 .select{|sg|
                   sg.ip_permissions
                     .find{|ipp|
                       ipp.ip_ranges
                         .find{|ipr| ipr.cidr_ip.eql?(office_ip) } } }

      # Go with teh most restrictive security group open to the office IP. TODO: ^^ make sure there are no port restrictions? or that 22 and 443 are open?
      groups.sort{|a,b| a.ip_permissions.size <=> b.ip_permissions.size}.first.group_id
    end


    def ssh_key(az)
      client = Aws::EC2::Client.new(region: az.chop)
      client.describe_key_pairs.key_pairs.find{|key_pair| key_pair.key_name.match(/dev-6fusion-dev/)}.key_name
    end

    def instance_type(str)
      puts "Checking #{str} for instance type"
      md = str.match(/(\p{L}{1,2}\d\.\d?(?:nano|small|medium|large|xlarge))/)
      md ? md[1] : 't2.xlarge'
    end

    def availability_zone(str)
      if md = str.match(/(\p{L}{2}-\p{L}+-\d\p{L})\b/)
        puts "md1: #{md[1]}"
        if az = availability_zones[md[1]]
          if az[:state].eql?('available')
            az
          else
            raise("Availability Zone #{az} is not currently available")
          end
        else
          raise("Availability Zone #{az} not found")
        end
      elsif md = str.match(/(\p{L}{2}-\p{L}+-\d)\b/)
        puts "md1 :: #{md[1]}"
        az, info = availability_zones.find{|k,v| v[:region_name].eql?(md[1])}
        if info
          if info[:state].eql?('available')
            az
          else
            raise("Availability Zone #{az} is not currently available")
          end
        else
          raise("Availability Zone #{az} not found")
        end
      elsif md = str.downcase.match(/(california|canada|ohio|oregon|virginia)/)
        region = case md[1]
                 when 'california' then 'us-west-1'
                 when 'canada' then 'ca-central-1'
                 when 'ohio' then 'us-east-2'
                 when 'oregon' then 'us-west-2'
                 when 'virginia' then 'us-east-1'
                 else 'us-east-2'
                 end
        # pick a random az from the region
        availability_zones.select{|az,value| value['region_name'].eql?(region) and value['state'].eql?('available')}.keys.sample
      else
        availability_zones.keys.select{|az| az.match(/us-\w+-\d.*/)}.reject{|az| az.match(/us-east-1/)}.keys.sample
      end

    end


    def aws_user_for(slack_user)
      mapping = { 'peyton'  => 'pvaughn',
                  'd-vison' => 'dseymour',
                  'lackey'  => 'rlackey' }
      mapping[slack_user] || slack_user
    end


    # FIXME put in redis, occasionally expire
    def availability_zones
      az = redis.get('availability_zones')
      if az
        JSON::parse(az)
      else
        begin
          h = {}
          regions.each do |region|
            Aws::EC2::Client.new(region: region)
              .describe_availability_zones.data.availability_zones
              .each{|az| h[az.zone_name] = { region_name: az.region_name, state: az.state } }
          end
          redis.set('availability_zones', h.to_json)
          redis.expire('availabity_zones', 24 * 7 * 3600)
          h
        end
      end
    end

    def regions
      # expire occasionally
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

    def office_ip
      # on the host, this IP is accessible at http://instance-data. Sadly, docker DNS doesn't seem to pick this up, so it's not available in the conatiner
      sg = Net::HTTP.get(URI.parse('http://169.254.169.254/latest/meta-data/security-groups'))

      client = Aws::EC2::Client.new
      @office_ip ||= client
                       .describe_security_groups
                       .security_groups
                       .find{|sg| sg.group_name.eql?('lita-ports')}
                       .ip_permissions
                       .find{|ipp| ipp.from_port == 22}
                       .ip_ranges
                       .first      # first/last - doesn't matter - ssh should only be open to the office IP
                       .cidr_ip
    end

    def coreos_image_id(region, response)
      redis.hget('coreos_image_id', region) ||
        begin
          response.reply("Retrieving latest CoreOS AMI for #{region}. This will take a moment... :clock3:")
          result = Aws::EC2::Client.new(region: region)
                                   .describe_images(owners:  ['aws-marketplace'],
                                                    filters: [{name: 'virtualization-type', values: ['hvm']},
                                                              {name: 'description', values: ['CoreOS*']}])
          latest = result.images.sort_by(&:creation_date).last
          redis.hset('coreos_image_id', region, latest.image_id)
          redis.expire('coreos_image_id', 24 * 7 * 3600)
          latest.image_id
        end
    end

  end
end

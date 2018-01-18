require 'base64'
require 'net/http'
require 'yaml'

require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def deploy_instance(response)

      begin
         # currently hard-coded to deploy a meter. need to figure out how to update user_data, and add tags later, etc
        options = response.matches[0][0]
        az = availability_zone(options)
        instance_type = instance_type(options)
        aws_user = aws_user_for(response.user.mention_name)


        if md = options.match(/=name=(?:"([^"]+)"|([^\s]+))/) # extracts name from: name="foo bar" or just name=foo or just name=foo bar=baz
          instance_name = "#{md[1]} (#{aws_user}-#{deploy_count(aws_user)})"
        else
          instance_name = "6fusion Meter (#{aws_user}-#{deploy_count(aws_user)})"
        end

        response.reply("Deploying #{instance_type} to #{az.chop}...")

        user_data = Base64.strict_encode64(render_template('cloud_config.yml', version: 'alpha'))

        puts "====== cloud config ======="
        puts user_data
        puts "==========================="

        ec2 = Aws::EC2::Resource.new(region: az.chop)

        block_device_mappings = [{ device_name: "/dev/xvda",
                                   ebs: {
                                     delete_on_termination: true,
                                     volume_size: volume_size(options),
                                     volume_type: volume_type(options) }}]
        instance_options = { image_id: coreos_image_id(az.chop, response),
                             min_count: 1,
                             max_count: 1,
                             key_name: ssh_key(az),
                             security_group_ids: [security_group(az)],
                             user_data: user_data,
                             instance_type: instance_type,
                             iam_instance_profile: { name: "ssm-full-access" },
                             placement: { availability_zone: az },
                             block_device_mappings: block_device_mappings }

        instance_options.merge!(subnet_id: subnet(options))
        instances = ec2.create_instances(instance_options)
        # Wait for the instance to be created, running, and passed status checks
        ec2.client.wait_until(:instance_running, {instance_ids: [instances[0].id]}){|w|
          w.interval = 10
          w.max_attempts = 100
          response.reply("Waiting for instance #{instances[0].id} to spin up...") }

        # FIXME this tag is not "correct" for `instance deploy` route
        instances.batch_create_tags({ tags: [{ key: 'Name', value: instance_name},
                                             { key: 'CostCenter', value: 'development' },
                                             { key: 'Owner', value: aws_user },
                                             { key: 'DeployedBy', value: 'lita' },
                                             { key: 'ApplicationRole', value: '6fusion-Meter' }
                                            ]})
        instance = Aws::EC2::Instance.new(instances.first.id, client: ec2.client)
        response.reply("Instance running. You can connect with:\n\n`ssh -i #{user_key_prefix(response)}#{ssh_key(az)}.pem core@#{instance.public_dns_name}`")
        instance
      rescue => e
        p e if e.message.match(/Encoded authorization failure/)
        response.reply(render_template('exception', exception: e))
        raise e
      end
    end

    def deploy_count(user)
      redis.incr("#{user}-deploy-count")
    end

    def deploy_meter(response)
      instance = deploy_instance(response)
        # Wait for the instance to be created, running, and passed status checks
# dry this up; passing ec2 into methods?
      options = response.matches[0][0]
      az = availability_zone(options)
      ec2 = Aws::EC2::Resource.new(region: az.chop)
      response.reply("Meter installation will begin after EC2 instance status checks complete... :clock3:")
      ec2.client.wait_until(:instance_status_ok, {instance_ids: [instance.id]}){}
      response.reply("Meter installation underway...")

      options = response.matches[0][0]
      az = availability_zone(options)
      ssm = Aws::SSM::Client.new(region: az.chop)

      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter installation',
            timeout_seconds: 1000,
            parameters: {
              commands: ['PATH="$PATH:/opt/bin" END_USER_LICENSE_ACCEPTED=yes /opt/bin/meterctl-alpha install-master > /root/install-stdout.log'],
              execution_timeout: 1000 } }

      resp = ssm.send_command(c)

      # ssm.wait_until{|waiter| p waiter;
      #   resp.command.status == 'Success' }
      # p "waiter done"

      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter installation',
            parameters: {
              commands: ['pgrep meterctl'] } }
      install_complete = false
      i = 0
      while !install_complete
        puts "install not complete, check ##{i}"
        sleep 20
        i += 1
        resp = ssm.send_command(c)
        r = ssm.get_command_invocation({ command_id: resp.command.command_id,
                                         instance_id: instance.id })
        install_complete = r.standard_output_content.empty?
        break if i == 20
      end
      #resp.instance_association_status_infos[0].output_url.s3_output_url.output_url #=> String
      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter kubeconfig',
            output_s3_bucket_name: '6fusion-dev-lita',
            output_s3_key_prefix: 'meter-installs',
            output_s3_region: 'us-east-11',
            parameters: {
              commands: ['/opt/bin/kubectl config view --flatten'] } }
      p "sending kubectl config view command"
      response = ssm.send_command(c)

      p response.inspect
      puts "===================================================================================================="
      p response.command

      # will need to sed private server: IP with public IP/host

      #   response.reply("Error installing meter: " + response.command.status_details)
      response.reply("Meter up and running")

      instance
    end

    def terminate_instance(response)
      instance_id = response.matches[0][0]
      ec2 = Aws::EC2::Resource.new(region: 'us-east-2') # store @ creation time in redis, retrieve; fallback to searching all of aws?

      instance = ec2.instance(instance_id)
      if instance.exists?
        case instance.state.code
        when 48  # terminated
          response.reply("Instance #{instance_id} is already terminated")
        when 64  # stopping
          response.reply("Instance #{instance_id} is shutting down")
        when 89  # stopped
          response.reply("Instance #{instance_id} is currently stopped, terminating")
          instance.terminate
        else
          instance.terminate
          response.reply("Terminating instance #{instance_id}")
        end
        else
        response.reply("Not able to find any instance with id #{instance_id}")
      end
    end

    ####################################################################################################
    # List operations
    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values: ['6fusion-Meter'] }])
    end
    def list_user_instances(response)
      list_instances(response, [{ name: 'tag:Owner', values: [aws_user_for(response.user.mention_name)] }])
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

    def set_user_ssh_key_path(response)
      user_path = response.matches[0][0]
      redis.hset('ssh_key_paths', response.user.mention_name, user_path.sub(%r|/$|, ''))
      response.reply("Key path preference saved")
    end
    
    private
    def volume_size(options)
      md = options.match(/\b(\d+)gi*b/i)
      md ? md[1] : 30
    end

    def volume_type(options)
      'gp2'
    end

    def subnet(options)
      case availability_zone(options)
      when /us-east-1/ then 'subnet-1d641037'
      else nil
      end
    end


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
      md = str.match(/(\p{L}{1,2}\d\.\d?(?:nano|micro|small|medium|large|xlarge))/)
      md ? md[1] : 'm4.xlarge'
    end

    def version(str)
      md = str.match(/([\d\.]+|alpha|beta)/)
      md ? md[1] : 'stable'
    end


    def availability_zone(str)
      str = 'ohio'
      az = if md = str.match(/(\p{L}{2}-\p{L}+-\d\p{L})\b/)
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
        p availability_zones.keys.select{|az| az.match(/us-\w+-\d.*/)}
        availability_zones.keys.select{|az| az.match(/us-\w+-\d.*/)}.reject{|az| az.match(/us-east-1/)}.keys.sample
      end
      az.match(/us-east-1/) ? 'us-east-1b' : az  # us-east-1 doesn't have a default vpc, and onyl 1 subnet, in this AZ
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
      redis.hget('meter_image_id', region) ||
        begin
          response.reply("Retrieving latest 6fusion Meter AMI for #{region}. This may take a moment... :clock3:")
          result = Aws::EC2::Client.new(region: region)
                     .describe_images(owners:  ['self'],
                                      filters: [{name: 'virtualization-type', values: ['hvm']},
                                                {name: 'name', values: ['6fusion Meter*']}])
          custom_images = result.images.select{|i| i.name.match(/6fusion.meter/i)}.sort_by(&:creation_date)
          latest = custom_images.empty? ? result.images.sort_by(&:creation_date).last : custom_images.last
          redis.hset('meter_image_id', region, latest.image_id)
          redis.expire('meter_image_id', 3600)
          latest.image_id
        end
    end

    def user_key_prefix(response)
      path = redis.hget('ssh_key_paths', response.user.mention_name)
      if path.nil?
        response.reply("You can set a path to your ssh keys - for future replies - with `lita  set ssh-key-path PATH`")
        ""
      else
        "#{path}/"
      end
    end


  end
end

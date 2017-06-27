require "spec_helper"

describe Lita::Handlers::MeterSidekick, lita_handler: true do


  describe "command : deploy operations" do
    it { is_expected.to route("deploy instance") }
    it { is_expected.to route("instance deploy") }
    it { is_expected.to route("deploy instance us-west-1") }
    it { is_expected.to route("deploy instance us-west-1 t2.nano") }
  end


  describe "command : meter operations" do
    it { is_expected.to route("meter latest") }
    it { is_expected.to route("latest release") }
  end

  describe "command : list operations" do
    it { is_expected.to route("list meters") }
    it { is_expected.to route("list instances") }

    it "reponds with a list of instances" do
      send_message("list instances")
      expect(replies.first).to match(/Name\s+ IP\s+ Status\s+ Type\s+ Owner\s+ Region\s+ Age.+/m)
    end
    it "reponds with a list of meter instances" do
      send_message("list meters")
      expect(replies.first).to match(/Name\s+ IP\s+ Status\s+ Type\s+ Owner\s+ Region\s+ Age.+/m)
    end
    it "reponds with a list of user instances" do
      send_message("list my instances")
      expect(replies.first).to eq('No matching instances found') # the lita 'test user' will not have any instances
    end
    it "reponds with a list of filtered instances" do
      send_message("list instances Owner=pvaughn")
      expect(replies.first).to match(/Name\s+ IP\s+ Status\s+ Type\s+ Owner\s+ Region\s+ Age.+/m)
    end

  end


end

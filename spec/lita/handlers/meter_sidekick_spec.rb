require "spec_helper"

describe Lita::Handlers::MeterSidekick, lita_handler: true do

  let(:botname) { "Lita" }

  # routes
  describe "command : meter latest" do
    it { is_expected.to route("#{botname} meter latest") }
  end

  describe "command : instances" do
    it { is_expected.to route("#{botname} instances") }

    it "reponds with a list of instances" do
      send_message("instances")
      expect(replies.first).to match(/Name\s+ IP\s+ Status\s+ Type\s+ Owner\s+ Region\s+ Age.+/m)
    end

  end


end

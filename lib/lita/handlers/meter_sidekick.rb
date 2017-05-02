module Lita
  module Handlers
    class MeterSidekick < Handler
      include ::LitaMeterSidekick::S3

      route(/meter latest/, :latest, help: { 'meter latest' => 'Links to installers for latest version of the meter' })

      Lita.register_handler(self)
    end
  end
end

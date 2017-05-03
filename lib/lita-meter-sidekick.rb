require 'lita'

Lita.load_locales Dir[File.expand_path(
  File.join('..', '..', 'locales', '*.yml'), __FILE__
)]

require 'lita-meter-sidekick/s3'
require 'lita-meter-sidekick/ec2'

require 'lita/handlers/meter_sidekick'

Lita::Handlers::MeterSidekick.template_root File.expand_path(
  File.join('..', '..', 'templates'),
 __FILE__
)

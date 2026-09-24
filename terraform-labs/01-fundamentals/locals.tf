locals {
  full_content = "${var.file_content} | environment=${var.environment}"
}

locals {

upper_zones = [
  for zone in var.availability_zones :
  upper(zone)
]

zones_with_a = [
  for zone in var.availability_zones :
  zone
  if endswith(zone, "a")
]

zone_map = {
  for zone in var.availability_zones :
  zone => upper(zone)
}

  environment_name = var.is_production ? "prod" : "dev"
}


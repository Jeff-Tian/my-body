locals {
  domain = "hardway.app"

  # Declarative DNS records. Add / remove entries here — `terraform apply`
  # will create / update / delete the corresponding Vercel DNS records.
  dns_records = {
    mybody_cname = {
      name  = "mybody"
      type  = "CNAME"
      value = "jeff-tian.github.io"
      ttl   = 60
    }
  }
}

resource "vercel_dns_record" "records" {
  for_each = local.dns_records

  domain = local.domain
  name   = each.value.name
  type   = each.value.type
  value  = each.value.value
  ttl    = each.value.ttl
}

output "records" {
  value = {
    for k, r in vercel_dns_record.records :
    k => "${r.type} ${r.name}.${r.domain} -> ${r.value} (ttl=${r.ttl})"
  }
}

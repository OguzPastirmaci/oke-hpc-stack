# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  dns_resolver = data.oci_core_vcn_dns_resolver_association.oke
  dns_view_id  = one(data.oci_dns_resolver.oke[*].default_view_id)
}

data "oci_core_vcn_dns_resolver_association" "oke" {
  vcn_id = module.oke.vcn_id
}

data "oci_dns_resolver" "oke" {
  depends_on  = [time_sleep.wait_3_min_resolver]
  count       = local.dns_resolver != null ? 1 : 0
  resolver_id = data.oci_core_vcn_dns_resolver_association.oke.dns_resolver_id
  scope       = "PRIVATE"
}

resource "oci_dns_zone" "oke" {
  depends_on     = [data.oci_dns_resolver.oke]
  compartment_id = one(data.oci_dns_resolver.oke[*].compartment_id)
  name           = format("oke.%v", local.state_id)

  zone_type = "PRIMARY"
  scope     = "PRIVATE"
  view_id   = local.dns_view_id
}

resource "time_sleep" "wait_3_min_resolver" {
  create_duration = "3m"
  depends_on      = [data.oci_core_vcn_dns_resolver_association.oke]
}
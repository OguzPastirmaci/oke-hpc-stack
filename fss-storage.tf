# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  fss_nsg_id      = module.oke.fss_nsg_id
  fss_subnet_id   = module.oke.fss_subnet_id
  fss_volume_name = format("oke-fss-%v", local.state_id)
  fss_ip_address  = data.oci_core_private_ip.fss_mount_target.ip_address
}

data "oci_core_private_ip" "fss_mount_target" {
  private_ip_id = try(oci_file_storage_mount_target.fss.private_ip_ids[0], null)
}

resource "oci_file_storage_file_system" "fss" {
  availability_domain = var.fss_ad
  compartment_id      = var.compartment_ocid
  display_name        = local.fss_volume_name
}

resource "oci_file_storage_mount_target" "fss" {
  availability_domain = oci_file_storage_file_system.fss.availability_domain
  compartment_id      = oci_file_storage_file_system.fss.compartment_id
  display_name        = local.fss_volume_name
  nsg_ids             = toset([local.fss_nsg_id])
  subnet_id           = local.fss_subnet_id
}

resource "oci_file_storage_export_set" "fss" {
  mount_target_id   = oci_file_storage_mount_target.fss.id
  max_fs_stat_bytes = 23843202333
  max_fs_stat_files = 223442
}

resource "oci_file_storage_export" "fss" {
  export_set_id  = oci_file_storage_export_set.fss.id
  file_system_id = oci_file_storage_file_system.fss.id
  path           = "/shared"
}
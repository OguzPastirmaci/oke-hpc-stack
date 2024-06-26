# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

terraform {
  experiments      = [module_variable_optional_attrs]
  required_version = ">= 1.2.0"
  
  required_providers {
    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 4.115.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.1"
    }
  }
}

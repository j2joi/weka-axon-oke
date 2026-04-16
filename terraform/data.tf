# Required to get the 'home_region'
data "oci_identity_region_subscriptions" "home_region_subscriptions" {
  tenancy_id = var.tenancy_ocid != "" ? var.tenancy_ocid : var.compartment_ocid
}

# Get all of the availability domains for the tenancy
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid != "" ? var.tenancy_ocid : var.compartment_ocid
}


# Get the public IP of the machine running Terraform
data "http" "my_public_ip" {
  url = "https://ipv4.icanhazip.com"
}

# Query all available OKE node pool images for the current region.
# Used to dynamically resolve the Ubuntu noble amd64 OKE image OCID.
data "oci_containerengine_node_pool_option" "oke_node_images" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_ocid
}

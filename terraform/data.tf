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

# ── Block volume data sources (Phase 2 — read after node pool is provisioned) ─
#
# These data sources depend on module.oke and are only evaluated when
# enable_block_volumes = true. On the first apply (Phase 1) they are skipped.
# Run a second `terraform apply` after Phase 1 to create and attach volumes.

# List node pools for the cluster, filtered by the known pool name.
data "oci_containerengine_node_pools" "by_cluster" {
  count          = local.enable_block_volumes ? 1 : 0
  compartment_id = var.compartment_ocid
  cluster_id     = module.oke.cluster_id
  name           = local.managed_node_pool_name
  depends_on     = [module.oke]
}

# Read full node pool detail: gives availability_domain and instance id per node.
data "oci_containerengine_node_pool" "managed" {
  count        = local.enable_block_volumes ? 1 : 0
  node_pool_id = data.oci_containerengine_node_pools.by_cluster[0].node_pools[0].id
  depends_on   = [module.oke]
}



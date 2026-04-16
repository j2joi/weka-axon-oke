# OKE module handles the creation and management of Networking, Cluster and Managed Nodes
module "oke" {
  source = "oracle-terraform-modules/oke/oci"
  version = "5.4.2"

  # Connects the "oke" module to "oracle/oci" provider
  providers = {
    oci.home = oci.home
  }

  # Identity and access parameters
  tenancy_id     = var.tenancy_ocid != "" ? null : var.compartment_ocid
  compartment_id = var.compartment_ocid
  region         = var.region
  # home_region          = data.oci_identity_region_subscriptions.home_region_subscriptions.region_subscriptions[0].region_name
  # home_region         = "eu-frankfurt-1"
  api_fingerprint      = var.fingerprint
  api_private_key_path = var.private_key_path
  user_id              = var.user_ocid

  # General OCI parameters
  # timezone = "Americas/Chicago"
  timezone = "America/New_York"

  # SSH keys
  ssh_public_key_path  = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path

  # Networking
  subnets = {
    cp       = { newbits = 13, netnum = 2, dns_label = "cp", create = "always" }
    int_lb   = { newbits = 11, netnum = 16, dns_label = "ilb", create = "always" }
    pub_lb   = { newbits = 11, netnum = 17, dns_label = "plb", create = "always" }
    workers  = { newbits = 2, netnum = 1, dns_label = "workers", create = "always" }
    pods     = { newbits = 2, netnum = 2, dns_label = "pods", create = "always" }
    bastion  = { newbits = 13, netnum = 3, dns_label = "bastion", create = "always" }
    operator = { newbits = 13, netnum = 4, dns_label = "operator", create = "always" }
  }

  # Simplify our demo deployment disabling the creation of a bastion
  # and an operator server.
  create_operator       = false
  create_bastion        = false
  bastion_allowed_cidrs = ["${trimspace(data.http.my_public_ip.response_body)}/32"]

  # Tune to only create the minimum permissions
  create_iam_resources         = true
  create_iam_autoscaler_policy = "never"
  create_iam_operator_policy   = "never"
  create_iam_kms_policy        = "never"
  create_iam_worker_policy     = "never" # Set to never to avoid Permissions Issues.



  # Cluster
  cluster_name       = "weka-oracle-tf"
  cluster_type       = "enhanced" # Required for self-managed nodes
  cni_type           = var.cni_type
  kubernetes_version = var.kubernetes_version
  pods_cidr          = "10.244.0.0/16"
  services_cidr      = "10.96.0.0/16"

  # Worker pool
  worker_pool_size = var.worker_pool_size
  worker_is_public = var.public_nodes
  worker_image_id   = local.effective_image_id
  worker_image_type = local.effective_image_type
  worker_image_os   = local.effective_image_os
  worker_shape = { shape = local.instance_shape, ocpus = 8, memory = 128, boot_volume_size = 200, boot_volume_vpus_per_gb = 20 }

  # Remove default cloud-init provided to Oracle Linux images
  worker_disable_default_cloud_init = true
  worker_pools                      = merge(local.self_managed, local.managed_nodes)

  # Enable values for testing and debugging the cluster
  allow_worker_ssh_access = true
  allow_rules_workers = {
    "Allow SSH ingress to workers from my public IP" = {
      protocol = 6, port = 22, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow TCP 15000 ingress to workers from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 6, port = 15000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow UDP 15000 ingress to workers from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 17, port = 15000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow TCP 14000 ingress to workers from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 6, port = 14000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow UDP 14000 ingress to workers from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 17, port = 14000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
  }

  # npn CNI: pods have their own NSG — mirror the WEKA GUI rule so pods are reachable too
  allow_rules_pods = {
    "Allow TCP 15000 ingress to pods from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 6, port = 15000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow UDP 15000 ingress to pods from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 17, port = 15000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow TCP 14000 ingress to pods from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 6, port = 14000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
    "Allow UDP 14000 ingress to pods from admin/bastion CIDR (WEKA GUI)" = {
      protocol = 17, port = 14000, source = "${trimspace(data.http.my_public_ip.response_body)}/32", source_type = "CIDR_BLOCK"
    }
  }

  control_plane_allowed_cidrs       = ["${trimspace(data.http.my_public_ip.response_body)}/32"]
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true

  # Enables output of cluster details
  output_detail = true
}

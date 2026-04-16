
locals {
  arch_to_shape = {
    "amd64" = "VM.DenseIO.E4.Flex" # Not supported by ubuntu minimal
    "arm64" = "VM.Standard.A1.Flex"
  }
  # instance_shape = local.arch_to_shape[var.architecture]
  instance_shape = var.instance_shape
  # 1. Strip the 'v' prefix if it exists
  clean_k8s_version = replace(var.kubernetes_version, "/^v/", "")

  # 2. Extract just the 'Major.Minor' (e.g., '1.33') using regex
  # This looks for the first two segments of the version string
  k8s_minor_key = regex("^(\\d+\\.\\d+)", local.clean_k8s_version)[0]

  # https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingubuntubasedworkernodes.htm
  # The lookup table for OKE node packages
  oke_packages = {
    "jammy" = {
      "1.27" = "oci-oke-node-all-1.27.10"
      "1.28" = "oci-oke-node-all-1.28.10"
      "1.29" = "oci-oke-node-all-1.29.1"
      "1.30" = "oci-oke-node-all-1.30.10"
      "1.31" = "oci-oke-node-all-1.31.10"
      "1.32" = "oci-oke-node-all-1.32.10"
      "1.33" = "oci-oke-node-all-1.33.1"
      "1.34" = "oci-oke-node-all-1.34.2"
    }
    "noble" = {
      "1.27" = "oci-oke-node-all-1.27.10"
      "1.28" = "oci-oke-node-all-1.28.10"
      "1.29" = "oci-oke-node-all-1.29.1"
      "1.30" = "oci-oke-node-all-1.30.10"
      "1.31" = "oci-oke-node-all-1.31.10"
      "1.32" = "oci-oke-node-all-1.32.10"
      "1.33" = "oci-oke-node-all-1.33.1"
      "1.34" = "oci-oke-node-all-1.34.2"
    }
  }

  # Add a node-pool if 'ubuntu_managed_nodes=true'
  self_managed = var.ol_managed_nodes ? {
    ol-8-10-OKE = {
      description                = "OKE-managed Node Pool with OKE OL image ",
      mode                       = "node-pool",
      create                     = true,
      # size                       = var.worker_pool_size,
      disable_default_cloud_init = false,
      disable_block_volume       = true,
      allow_autoscaler           = false, # Required if no privileges to create dynamic groups
      cloud_init = [
        {
          content      = base64encode(file("./user-data/managed_OL_OKE.yaml")),
          content_type = "text/cloud-config",
        },
      ]
    },
  } : {}
  managed_nodes = var.ubuntu_managed_nodes ? {
    ubuntu-24-4-OKE = {
      description = "OKE-managed Node Pool with Ubuntu Image",
      mode                 = "node-pool",
      create      = true,
      # size        = var.worker_pool_size,
      disable_block_volume = true,
      allow_autoscaler = false, # Required if no privileges to create dynamic groups
      cloud_init = [
        {
          content      = base64encode(file("./user-data/managed_ubuntu.yaml")),
          content_type = "text/cloud-config",
        },
      ]
    },
  } : {}

  # Resolve image mode: custom (image_id) takes priority, then explicit type, then default
  # Architecture derived from instance shape: A1/A2 = arm64, everything else = amd64
  _image_arch = length(regexall("A[12]\\.", var.instance_shape)) > 0 ? "arm64" : "amd64"

  # OS version string derived from ubuntu_release
  _ubuntu_os_version = var.ubuntu_release == "noble" ? "24.04" : "22.04"

  # Dynamically resolved Ubuntu OKE image OCID.
  # Filters oci_containerengine_node_pool_option sources by:
  #   - arch     (derived from instance_shape)
  #   - release  (ubuntu_release: noble/jammy)
  #   - k8s ver  (clean_k8s_version: e.g. "1.33.1")
  # Sorts candidates lexicographically (YYYYMMDD date in name), picks most recent.
  # Returns null when ubuntu_release is empty (Oracle Linux path).
  ubuntu_oke_image_id = var.ubuntu_release == "" ? null : try(
    element(
      split("###",
        element(
          reverse(sort([
            for s in data.oci_containerengine_node_pool_option.oke_node_images.sources :
            "${s.source_name}###${s.image_id}"
            if startswith(s.source_name,
                 "ubuntu-${local._image_arch}-minimal-${local._ubuntu_os_version}-${var.ubuntu_release}-") &&
               endswith(s.source_name, "-OKE-${local.clean_k8s_version}")
          ])),
          0
        )
      ),
      1
    ),
    null
  )

  # Explicit var.image_id takes priority.
  # Ubuntu managed nodes: resolve dynamically via node_pool_option lookup.
  # Oracle Linux managed nodes: null — OKE module auto-selects the OL image.
  effective_image_id = (
    var.image_id != null       ? var.image_id :
    var.ubuntu_managed_nodes   ? local.ubuntu_oke_image_id :
    var.ol_managed_nodes       ? null :
    null
  )

  # Use "custom" type whenever an OCID is resolved — bypasses broken setintersection in OKE module
  effective_image_type = (
    local.effective_image_id != null ? "custom" :
    var.worker_image_type != null    ? var.worker_image_type :
    "oke"
  )

  # os is irrelevant for custom image type
  effective_image_os = (
    local.effective_image_id != null ? null :
    var.worker_image_os
  )

  # Guard: ubuntu_release must be "jammy" or "noble" when ubuntu_managed_nodes = true
  _validate_ubuntu_release = (
    var.ubuntu_managed_nodes && !contains(["jammy", "noble"], var.ubuntu_release)
    ? tobool("ERROR: ubuntu_release variable must be 'jammy' or 'noble' when ubuntu_managed_nodes = true")
    : true
  )

  # Guard: self-managed nodes are raw VMs and always need an explicit image OCID
  _validate_self_managed_image = (
    var.ol_managed_nodes && var.ubuntu_managed_nodes
    ? tobool("ERROR: ol_managed_nodes and ubuntu_mananaged_nodes can't be both set to true")
    : true
  )

    
}

# Variables for the OKE cluster deployment

variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "API Key Fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to the OCI API private key"
  type        = string
}

variable "region" {
  description = "OCI Region"
  type        = string
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key"
  type        = string
  default =  null
}

variable "kubernetes_version" {
  description = "Version used for the OKE control plane"
  type        = string
  default     = "v1.32.1"
}

variable "cni_type" {
  description = "Container networking type used within the OKE cluster (default 'npn')"
  type        = string
  default     = "npn"

  validation {
    condition     = contains(["flannel", "npn"], var.cni_type)
    error_message = "Invalid cni_type. Options include 'flannel' and 'npn'."
  }
}

variable "architecture" {
  description = "CPU Architecture to use for worker instances. Must match the provided 'image_id'. (default 'amd64')"
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "Invalid architecture. Options include 'amd64' and 'arm64'."
  }
}

variable "ubuntu_managed_nodes" {
  description = "Adds Ubuntu managed nodes to the cluster when supplied (default 'false')"
  type        = bool
  default     = false
}

variable "ol_managed_nodes" {
  description = "Adds Oracle Linux self-managed nodes to the cluster when supplied (default 'false')"
  type        = bool
  default     = false
}

variable "public_nodes" {
  description = "Enable the worker nodes to be public (default 'false')"
  type        = bool
  default     = false
}

variable "image_id" {
  description = "OCID of the Ubuntu OKE image to be used"
  type        = string
  default     = null
}

variable "ubuntu_release" {
  description = "If ubuntu is used. Supported o"
  type        = string
  default     = ""
  validation {
    condition     = contains(["jammy", "noble", ""], var.ubuntu_release)
    error_message = "Invalid Ubunty OS Release Name supported. Options include 'jammy' and 'noble'."
  }
}

variable "worker_image_type" {
  description = "OKE image type when no custom image_id is provided ('oke' or 'platform'). Mutually exclusive with image_id."
  type        = string
  default     = null

  validation {
    condition     = var.worker_image_type == null || contains(["oke", "platform"], coalesce(var.worker_image_type, ""))
    error_message = "worker_image_type must be 'oke' or 'platform' (use image_id for 'custom')."
  }
}

variable "worker_image_os" {
  description = "OS name for OKE/platform image selection. Used when image_id is not set. (default 'Oracle Linux')"
  type        = string
  default     = "Oracle Linux"

  validation {
    condition     = contains(["Oracle Linux", "Canonical Ubuntu"], var.worker_image_os)
    error_message = "worker_image_os must be 'Oracle Linux' or 'Canonical Ubuntu'."
  }
}

variable "worker_pool_size" {
  description = "Number of worker nodes in each node pool. Minimum 7 (WEKA requires at least 7 backend nodes)."
  type        = number
  # default     = 7

  validation {
    condition     = var.worker_pool_size >= 7
    error_message = "worker_pool_size must be at least 7."
  }
}

variable "instance_shape" {
  description = "Shape for Worker Nodes on OKE. (Options 'BM.DenseIO.E4.128 , VM.DenseIO.E4.Flex')"
  type        = string
  # default     = "BM.DenseIO.E4.128"
  validation {
    condition = contains(["VM.DenseIO.E4.Flex","VM.DenseIO.E5.Flex", "BM.DenseIO.E4.128" ], var.instance_shape)
    error_message = "instance_shape must be 'VM.DenseIO.E4.Flex' or 'VM.DenseIO.E4.Flex' or 'BM.DenseIO.E4.128' "
  }
}


# Cluster
output "cluster_id" { value = module.oke.cluster_id }
output "cluster_endpoints" { value = module.oke.cluster_endpoints }
output "cluster_kubeconfig" { value = module.oke.cluster_kubeconfig }
output "cluster_ca_cert" { value = module.oke.cluster_ca_cert }
output "apiserver_private_host" { value = module.oke.apiserver_private_host }

# Networking
output "vcn_id" { value = module.oke.vcn_id }
output "worker_subnet_id" { value = module.oke.worker_subnet_id }


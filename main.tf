data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

module "networking" {
  source                = "./modules/networking"
  compartment_ocid      = var.compartment_ocid
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
}

# module "iam" {
#   source           = "./modules/iam"
#   tenancy_ocid     = var.tenancy_ocid
#   compartment_ocid = var.compartment_ocid
# }

module "loadbalancer" {
  source           = "./modules/loadbalancer"
  compartment_ocid = var.compartment_ocid
  subnet_pub_id    = module.networking.subnet_pub_id
}

module "database" {
  source              = "./modules/database"
  compartment_ocid    = var.compartment_ocid
  subnet_db_id        = module.networking.subnet_db_id
  availability_domain = local.availability_domain
  admin_password      = var.db_admin_password
}

module "compute" {
  source              = "./modules/compute"
  compartment_ocid    = var.compartment_ocid
  availability_domain = local.availability_domain
  subnet_masters_id   = module.networking.subnet_masters_id
  subnet_workers_id   = module.networking.subnet_workers_id
  ssh_authorized_keys = var.ssh_authorized_keys
  # vault_id            = module.iam.vault_id
  # key_id              = module.iam.key_id
  worker_subnet_cidr  = "10.0.102.0/24"
  lb_id               = module.loadbalancer.lb_id
  lb_backend_set_name = module.loadbalancer.backend_set_name
  image_id            = var.image_id

  # depends_on = [module.iam]
}

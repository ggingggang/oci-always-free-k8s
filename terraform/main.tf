data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# ──────────────────────────────────────────
# Networking (VCN, Subnets, Security Lists, Bastion)
# ──────────────────────────────────────────
module "networking" {
  source                = "./modules/networking"
  compartment_ocid = var.compartment_ocid
}

# ──────────────────────────────────────────
# OKE Cluster + Node Pool
# ──────────────────────────────────────────
module "oke" {
  source              = "./modules/oke"
  compartment_ocid    = var.compartment_ocid
  vcn_id              = module.networking.vcn_id
  subnet_oke_api_id   = module.networking.subnet_oke_api_id
  subnet_pub_id       = module.networking.subnet_pub_id
  subnet_workers_id   = module.networking.subnet_workers_id
  availability_domain = local.availability_domain
  kubernetes_version  = var.kubernetes_version
  ssh_authorized_keys = var.ssh_authorized_keys
  user_data_file      = "./modules/oke/scripts/node_pool_init.sh"
  endpoint_nsg_ids    = [module.iam.nsg_public_id]
}

# ──────────────────────────────────────────
# IAM (Dynamic Group, Policy, NSG)
# ──────────────────────────────────────────
module "iam" {
  source           = "./modules/iam"
  compartment_ocid = var.compartment_ocid
  vcn_id           = module.networking.vcn_id
  allowed_cidr     = var.allowed_cidr
}

# ──────────────────────────────────────────
# Block Volume (Always Free: 200GB total incl. boot)
# Boot 2x47GB=94GB → PV available ~106GB (2 vols)
# ──────────────────────────────────────────
# module "storage" {
#   source              = "./modules/storage"
#   compartment_ocid    = var.compartment_ocid
#   availability_domain = local.availability_domain
# }

#──────────────────────────────────────────
# HeatWave MySQL (Always Free)
#──────────────────────────────────────────
module "database" {
  source              = "./modules/database"
  compartment_ocid    = var.compartment_ocid
  subnet_db_id        = module.networking.subnet_db_id
  availability_domain = local.availability_domain
  admin_password      = var.db_admin_password
}

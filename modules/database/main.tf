terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# HeatWave MySQL (Always Free)
# ──────────────────────────────────────────
resource "oci_mysql_mysql_db_system" "heatwave" {
  compartment_id      = var.compartment_ocid
  display_name        = "heatwave-main"
  availability_domain = var.availability_domain
  subnet_id           = var.subnet_db_id
  shape_name          = "MySQL.Free"

  admin_username = var.admin_username
  admin_password = var.admin_password

  data_storage_size_in_gb = 50

  deletion_policy {
    automatic_backup_retention = "DELETE"
    final_backup               = "SKIP_FINAL_BACKUP"
    is_delete_protected        = false
  }
}

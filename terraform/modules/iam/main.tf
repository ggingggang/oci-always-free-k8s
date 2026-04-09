terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# OKE Node IAM
# ──────────────────────────────────────────
# 현재 Basic Cluster + HeatWave 구성에서는 별도 IAM 정책 불필요.
#
# 추후 노드에서 OCI 서비스 접근이 필요한 경우 아래를 참고:
#
# 1. OCIR (Container Registry) 프라이빗 이미지 pull
#    → Dynamic Group + Policy "Allow dynamic-group ... to read repos in tenancy"
#
# 2. Object Storage 접근 (PersistentVolume 등)
#    → Policy "Allow dynamic-group ... to manage object-family in compartment ..."
#
# 3. OCI Vault / Secrets (민감 정보 주입)
#    → Dynamic Group + Policy "Allow dynamic-group ... to read secret-family in tenancy"
#
# ──────────────────────────────────────────

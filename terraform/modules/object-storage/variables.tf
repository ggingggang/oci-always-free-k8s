variable "compartment_ocid" {
  type = string
}

variable "region" {
  type        = string
  description = "S3-compat endpoint 구성용 (e.g. ap-tokyo-1)"
}

variable "bucket_names" {
  type        = list(string)
  description = "생성할 Object Storage 버킷 이름 목록"
}

# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  prefix = "${var.prefix}-${var.timestamp}-${var.suffix}"
  services = [
    # trimmed down list of services, to be extended as needed
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "serviceusage.googleapis.com",
    "stackdriver.googleapis.com",
    "storage-component.googleapis.com",
    "storage.googleapis.com",
    "servicenetworking.googleapis.com",
    "dns.googleapis.com",
  ]
  services-svc = [
    # trimmed down list of services, to be extended as needed
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}

resource "google_folder" "folder" {
  display_name = "E2E Tests ${var.timestamp}-${var.suffix}"
  parent       = var.parent
}

resource "google_project" "project" {
  name            = "${local.prefix}-prj"
  billing_account = var.billing_account
  folder_id       = google_folder.folder.id
  project_id      = "${local.prefix}-prj"
}

resource "google_project_service" "project_service" {
  for_each                   = toset(local.services)
  service                    = each.value
  project                    = google_project.project.project_id
  disable_dependent_services = true
}

resource "google_project" "service_project_1" {
  name            = "${local.prefix}-prj-1"
  billing_account = var.billing_account
  folder_id       = google_folder.folder.id
  project_id      = "${local.prefix}-prj-1"
}

resource "google_project_service" "service_project_1_service" {
  for_each                   = toset(local.services-svc)
  service                    = each.value
  project                    = google_project.service_project_1.project_id
  disable_dependent_services = true
}

resource "google_project" "service_project_2" {
  name            = "${local.prefix}-prj-2"
  billing_account = var.billing_account
  folder_id       = google_folder.folder.id
  project_id      = "${local.prefix}-prj-2"
}

resource "google_project_service" "service_project_2_service" {
  for_each                   = toset(local.services-svc)
  service                    = each.value
  project                    = google_project.service_project_2.project_id
  disable_dependent_services = true
}

resource "google_storage_bucket" "bucket" {
  location      = var.region
  name          = "${local.prefix}-bucket"
  project       = google_project.project.project_id
  force_destroy = true
  depends_on    = [google_project_service.project_service]
}

resource "google_compute_network" "network" {
  name                    = "e2e-test"
  project                 = google_project.project.project_id
  auto_create_subnetworks = false
  depends_on              = [google_project_service.project_service]
}

resource "google_compute_subnetwork" "subnetwork" {
  ip_cidr_range = "10.0.16.0/24"
  name          = "e2e-test-1"
  network       = google_compute_network.network.name
  project       = google_project.project.project_id
  region        = var.region
}

resource "google_service_account" "service_account" {
  account_id = "e2e-service-account"
  project    = google_project.project.project_id
  depends_on = [google_project_service.project_service]
}

resource "local_file" "terraform_tfvars" {
  filename = "e2e_tests.tfvars"
  content = templatefile("e2e_tests.tfvars.tftpl", {
    bucket             = google_storage_bucket.bucket.name
    billing_account_id = var.billing_account
    organization_id    = var.organization_id
    folder_id          = google_folder.folder.folder_id
    prefix             = local.prefix
    project_id         = google_project.project.project_id
    service_project_1_project_id = google_project.service_project_1.project_id
    service_project_2_project_id = google_project.service_project_2.project_id
    region             = var.region
    group_email        = var.group_email
    user_email         = var.user_email
    service_account = {
      id        = google_service_account.service_account.id
      email     = google_service_account.service_account.email
      iam_email = "serviceAccount:${google_service_account.service_account.email}"
    }
    subnet = {
      name          = google_compute_subnetwork.subnetwork.name
      region        = google_compute_subnetwork.subnetwork.region
      ip_cidr_range = google_compute_subnetwork.subnetwork.ip_cidr_range
      self_link     = google_compute_subnetwork.subnetwork.self_link
    }
    vpc = {
      name      = google_compute_network.network.name
      self_link = google_compute_network.network.self_link
      id        = google_compute_network.network.id
    }
  })
}

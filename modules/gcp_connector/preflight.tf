##################################################
# Plan-time checks
##################################################
# Before any write, the plan checks that the management project and every VM
# target project exist, are ACTIVE and belong to organization_id through any
# folder depth. It also stops when an organization audit exemption suppresses
# an audit event that the connector needs, and, with manage_audit_config =
# false, when a required audit log type is not on (audit.tf). Every resource depends on
# terraform_data.preflight, directly or through the management project APIs,
# so a failed check creates nothing.

locals {
  # The management project always. VM target projects only when VM scanning
  # is on.
  checked_projects = toset(concat([local.project], tolist(local.vm_targets)))

  project_records = {
    for p in local.checked_projects : p => [
      for r in data.google_projects.checked[p].projects : r if r.project_id == p
    ]
  }

  # Project ID => project number. "0" stands in when the record is missing or
  # ambiguous; it is never applied, because every resource depends on
  # terraform_data.preflight, whose precondition then fails.
  project_numbers = {
    for p, rs in local.project_records : p => length(rs) == 1 ? try(rs[0].number, "0") : "0"
  }

  # Project ID => direct parent, or null when the record is missing or ambiguous.
  project_parents = {
    for p, rs in local.project_records : p => length(rs) == 1 ? rs[0].parent : null
  }

  folder_parents = {
    for p, parent in local.project_parents : p => parent.id
    if parent != null && try(parent.type, "") == "folder"
  }

  # Project ID => organization ID, through any folder depth.
  project_organizations = {
    for p, parent in local.project_parents : p => (
      parent == null ? null :
      try(parent.type, "") == "organization" ? try(parent.id, null) :
      try(parent.type, "") == "folder" ? trimprefix(try(data.google_folder.parent[p].organization, ""), "organizations/") :
      null
    )
  }

  project_defects = sort(concat(
    [for p, rs in local.project_records : "${p}: expected exactly one project record with this ID, found ${length(rs)} (check that it exists and that the caller has resourcemanager.projects.get)" if length(rs) != 1],
    # HCL evaluates both sides of &&, so rs[0] is read through try().
    [for p, rs in local.project_records : "${p}: lifecycleState is ${try(rs[0].lifecycle_state, "")}, expected ACTIVE" if length(rs) == 1 && try(rs[0].lifecycle_state, "") != "ACTIVE"],
    [for p, o in local.project_organizations : "${p}: belongs to organization ${coalesce(o, "<none: standalone project or unreadable ancestry>")}, expected ${local.org}" if length(local.project_records[p]) == 1 && o != local.org],
  ))
}

# A list filtered by ID returns an empty list for a missing or unreadable
# project instead of an error, so the defect message can name the project.
data "google_projects" "checked" {
  for_each = local.checked_projects

  filter = "id:${each.value}"
}

# A denied folder read fails this data source, and the plan stops with the
# provider's error. Data sources are read before any resource, so nothing is
# created.
data "google_folder" "parent" {
  for_each = local.folder_parents

  folder              = "folders/${each.value}"
  lookup_organization = true
}

resource "terraform_data" "preflight" {
  input = {
    organization = local.org
    project      = local.project
  }

  lifecycle {
    precondition {
      condition     = length(local.project_defects) == 0
      error_message = <<-EOT
        Project check failed before any write:
        ${join("\n", local.project_defects)}
        Nothing has been created.
      EOT
    }

    precondition {
      condition     = length(local.audit_required_exemptions) == 0
      error_message = <<-EOT
        Organization ${local.org} exempts principals from audit events that the connector requires, so the connector would miss their activity:
        ${join("\n", local.audit_required_exemptions)}
        This module does not remove an existing audit exemption. Remove those exemptedMembers from the organization audit configuration, then run the plan again. Nothing has been created.
      EOT
    }

    # With manage_audit_config = false another stack owns the audit
    # configuration, so the module only checks that the log types it needs are on.
    precondition {
      condition     = var.manage_audit_config || length(local.audit_missing) == 0
      error_message = <<-EOT
        manage_audit_config is false, but organization ${local.org} does not enable these audit log types that the connector requires:
        ${join("\n", local.audit_missing)}
        Enable them in the configuration that owns the organization audit configuration, or set manage_audit_config = true. Nothing has been created.
      EOT
    }
  }
}

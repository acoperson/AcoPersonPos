import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const approvals = read("../supabase/migrations/20261108165858_business_application_and_plan_approval_flow.sql");
const workflows = read("../supabase/migrations/20261108231500_platform_and_shift_workflows.sql");
const hardening = read("../supabase/migrations/20261109000100_fix_public_qr_payment_proof_storage_policies.sql");

assert.match(hardening, /p_requested_plan is null or p_requested_plan not in \('free','business'\)/);
assert.match(approvals, /values\(v_org,'free','active',now\(\),null\)/);
assert.match(approvals, /if auth\.uid\(\) is null or not public\.is_platform_admin\(\) then raise exception 'Platform admin access required'/);
assert.match(approvals, /application_type='upgrade' and status='pending'/);
assert.match(workflows, /create or replace function public\.open_cashier_shift/);
assert.match(workflows, /create or replace function public\.close_cashier_shift/);
assert.match(workflows, /create or replace function public\.review_qr_payment/);
assert.match(hardening, /storage\.foldername\(storage\.objects\.name\)/);
assert.doesNotMatch(hardening, /storage\.foldername\(s\.name\)/);
assert.match(hardening, /create or replace function public\.claim_employee_invites/);
assert.match(hardening, /active_organization_id = coalesce\(public\.profiles\.active_organization_id,excluded\.active_organization_id\)/);
assert.match(hardening, /shifts_one_open_per_cashier_idx/);
assert.match(hardening, /attendance_one_open_per_employee_idx/);
assert.match(hardening, /business_applications_one_pending_new_business_per_user_idx/);
assert.match(hardening, /business_applications_one_pending_upgrade_per_org_idx/);
assert.match(hardening, /Produk duplikat tidak diperbolehkan dalam keranjang/);
assert.match(hardening, /p_requested_plan is distinct from 'business'/);
for (const index of [
  "attendance_store_id_idx",
  "business_applications_organization_id_idx",
  "business_applications_reviewed_by_idx",
  "employee_invites_invited_by_idx",
  "inventory_movements_created_by_idx",
  "inventory_movements_store_id_idx",
  "payment_confirmations_reviewed_by_idx",
  "payment_confirmations_store_id_idx",
  "sale_items_sale_id_idx",
  "schedules_store_id_idx",
  "shifts_store_id_idx"
]) assert.match(hardening, new RegExp(index));


console.log("ACOPOS migration invariants: PASS");

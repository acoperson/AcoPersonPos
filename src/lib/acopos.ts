import { supabase } from "./supabase";

export type WorkspaceProduct = {
  id: string;
  name: string;
  category: string;
  price: number;
  stock: number;
  sku: string;
};
export type WorkspaceOrder = {
  id: string;
  customer: string;
  total: number;
  status: string;
  time: string;
  items: number;
};
export type WorkspaceBranch = { id: string; name: string; address: string | null; qr_slug: string | null; is_active: boolean };
export type WorkspaceEmployee = { id: string; name: string; role: string; store_id: string | null; email?: string };

function requireClient() {
  if (!supabase) throw new Error("Supabase belum dikonfigurasi.");
  return supabase;
}

export async function loadAcoWorkspace(userId: string, requestedStoreId?: string) {
  const db = requireClient();
  const { data: profile, error: profileError } = await db
    .from("profiles")
    .select("id,full_name,active_organization_id")
    .eq("id", userId)
    .maybeSingle();
  if (profileError) throw profileError;

  await db.rpc("claim_employee_invites");
  const [memberResult, adminCheck] = await Promise.all([
    db.from("memberships").select("organization_id,user_id,role,store_id").eq("user_id", userId),
    db.rpc("is_platform_admin")
  ]);
  if (memberResult.error) throw memberResult.error;
  const memberships = memberResult.data ?? [];
  const isPlatformAdmin = adminCheck.data === true;
  if (!memberships.length) return { needsOnboarding: true as const, profile, isPlatformAdmin };

  const chosen = memberships.find((m: any) => m.organization_id === profile?.active_organization_id) ?? memberships[0];
  const organizationId = chosen.organization_id as string;
  const { data: organization, error: orgError } = await db
    .from("organizations")
    .select("id,name,slug")
    .eq("id", organizationId)
    .single();
  if (orgError) throw orgError;

  const [storeResult, productResult, salesResult, membershipResult, planResult] = await Promise.all([
    db.from("stores").select("id,organization_id,name,address,qr_slug,is_active").eq("organization_id", organizationId).order("created_at"),
    db.from("products").select("id,name,sku,selling_price,is_available,category_id").eq("organization_id", organizationId).eq("is_available", true).order("name"),
    db.from("sales").select("id,receipt_number,total,payment_status,created_at,cashier_user_id").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(30),
    db.from("memberships").select("id,user_id,role,store_id").eq("organization_id", organizationId),
    db.from("subscriptions").select("plan_name,status,starts_at,ends_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(1).maybeSingle()
  ]);
  if (storeResult.error) throw storeResult.error;
  if (productResult.error) throw productResult.error;
  if (salesResult.error) throw salesResult.error;
  if (membershipResult.error) throw membershipResult.error;

  const stores = (storeResult.data ?? []) as any[];
  const activeStore = stores.find((s) => s.id === requestedStoreId) ?? stores.find((s) => s.id === chosen.store_id) ?? stores.find((s) => s.is_active) ?? stores[0];
  const storeId = activeStore?.id as string | undefined;
  const [inventoryResult, profileResult, shiftResult, planCatalogResult, attendanceResult, customerResult, tabResult, reservationResult, qrOrderResult, paymentConfirmationResult] = await Promise.all([
    storeId ? db.from("store_inventory").select("product_id,quantity,low_stock_threshold").eq("store_id", storeId) : Promise.resolve({ data: [], error: null } as any),
    db.from("profiles").select("id,full_name").in("id", (membershipResult.data ?? []).map((m: any) => m.user_id)),
    storeId ? db.from("shifts").select("id,status,cashier_user_id,opening_cash,opened_at").eq("store_id", storeId).eq("cashier_user_id", userId).eq("status", "open").order("opened_at", { ascending: false }).limit(1).maybeSingle() : Promise.resolve({ data: null, error: null } as any),
    db.from("subscription_plans").select("code,name,price_idr,billing_period,is_paid,is_active,duration_days,branch_limit,features").eq("is_active", true).order("price_idr"),
    storeId ? db.from("attendance").select("id,employee_user_id,clock_in,clock_out,status,note").eq("store_id", storeId).order("clock_in", { ascending: false }).limit(30) : Promise.resolve({ data: [], error: null } as any),
    storeId ? db.from("customers").select("id,full_name,phone,email,member_code,points,store_id,created_at").or("store_id.eq." + storeId + ",store_id.is.null").order("created_at", { ascending: false }).limit(100) : Promise.resolve({ data: [], error: null } as any),
    storeId ? db.from("customer_tabs").select("id,customer_name,amount,paid_amount,due_date,status,created_at").eq("store_id", storeId).order("created_at", { ascending: false }).limit(100) : Promise.resolve({ data: [], error: null } as any),
    storeId ? db.from("reservations").select("id,customer_name,customer_phone,reservation_at,party_size,status,notes").eq("store_id", storeId).order("reservation_at", { ascending: true }).limit(100) : Promise.resolve({ data: [], error: null } as any),
    storeId ? db.from("qr_orders").select("id,order_number,customer_name,status,total,created_at").eq("store_id", storeId).order("created_at", { ascending: false }).limit(50) : Promise.resolve({ data: [], error: null } as any),
    storeId ? db.from("payment_confirmations").select("id,order_id,status,proof_image_url,created_at").eq("store_id", storeId).order("created_at", { ascending: false }).limit(50) : Promise.resolve({ data: [], error: null } as any)
  ]);
  if (inventoryResult.error) throw inventoryResult.error;
  if (profileResult.error) throw profileResult.error;
  if (attendanceResult.error) throw attendanceResult.error;
  if (customerResult.error) throw customerResult.error;
  if (tabResult.error) throw tabResult.error;
  if (reservationResult.error) throw reservationResult.error;
  if (qrOrderResult.error) throw qrOrderResult.error;
  if (paymentConfirmationResult.error) throw paymentConfirmationResult.error;

  const inventory = new Map((inventoryResult.data ?? []).map((r: any) => [r.product_id, r]));
  const profileMap = new Map((profileResult.data ?? []).map((p: any) => [p.id, p.full_name]));
  const products: WorkspaceProduct[] = (productResult.data ?? []).map((p: any) => {
    const stock = inventory.get(p.id) as any;
    return { id: p.id, name: p.name, category: p.category_id ? "Produk" : "Umum", price: Number(p.selling_price), stock: Number(stock?.quantity ?? 0), sku: p.sku ?? "" };
  });
  const orders: WorkspaceOrder[] = (salesResult.data ?? []).map((s: any) => ({
    id: s.receipt_number,
    customer: "Walk-in Customer",
    total: Number(s.total),
    status: s.payment_status === "paid" ? "Selesai" : s.payment_status === "refunded" ? "Dikembalikan" : "Menunggu",
    time: new Date(s.created_at).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" }),
    items: 0
  }));
  const employees: WorkspaceEmployee[] = (membershipResult.data ?? []).map((m: any) => ({
    id: m.user_id,
    name: profileMap.get(m.user_id) ?? "Pengguna",
    role: m.role,
    store_id: m.store_id
  }));
  return {
    needsOnboarding: false as const,
    profile,
    organization,
    organizationId,
    stores: stores as WorkspaceBranch[],
    activeStore,
    products,
    orders,
    employees,
    attendance: attendanceResult.data ?? [],
    customers: customerResult.data ?? [],
    customerTabs: tabResult.data ?? [],
    reservations: reservationResult.data ?? [],
    qrOrders: qrOrderResult.data ?? [],
    paymentConfirmations: paymentConfirmationResult.data ?? [],
    subscription: planResult.data,
    plans: planCatalogResult.data ?? [],
    activeShiftId: shiftResult.data?.id ?? null,
    isPlatformAdmin
  };
}

export async function createFreeBusiness(businessName: string, storeName: string) {
  const db = requireClient();
  const { data, error } = await db.rpc("submit_business_application", {
    p_business_name: businessName,
    p_store_name: storeName,
    p_requested_plan: "free",
    p_applicant_note: null
  });
  if (error) throw error;
  return data;
}

export async function createProductForStore(input: {
  organizationId: string; storeId: string; name: string; sku: string; price: number; stock: number;
}) {
  const db = requireClient();
  const { data: product, error } = await db.from("products").insert({
    organization_id: input.organizationId,
    name: input.name,
    sku: input.sku || null,
    selling_price: input.price,
    cost_price: 0,
    stock_quantity: input.stock,
    is_available: true
  }).select("id").single();
  if (error) throw error;
  const { error: inventoryError } = await db.from("store_inventory").insert({
    organization_id: input.organizationId,
    store_id: input.storeId,
    product_id: product.id,
    quantity: input.stock,
    low_stock_threshold: 0
  });
  if (inventoryError) throw inventoryError;
  return product;
}

export async function completeSale(input: {
  storeId: string; items: { product_id: string; quantity: number }[]; paymentMethod: string; note?: string;
}) {
  const db = requireClient();
  const { data: userResult, error: userError } = await db.auth.getUser();
  if (userError) throw userError;
  if (!userResult.user) throw new Error("Sesi login tidak ditemukan.");

  let shiftId: string | null = null;
  const { data: existingShift, error: shiftReadError } = await db.from("shifts")
    .select("id").eq("store_id", input.storeId).eq("cashier_user_id", userResult.user.id).eq("status", "open")
    .order("opened_at", { ascending: false }).limit(1).maybeSingle();
  if (shiftReadError) throw shiftReadError;
  shiftId = existingShift?.id ?? null;

  if (!shiftId) {
    const { data, error } = await db.rpc("open_cashier_shift", { p_store_id: input.storeId, p_opening_cash: 0 });
    if (error) throw error;
    shiftId = data as string;
  }

  const { data, error } = await db.rpc("complete_pos_sale", {
    p_store_id: input.storeId,
    p_shift_id: shiftId,
    p_items: input.items,
    p_discount: 0,
    p_payment_method: input.paymentMethod,
    p_note: input.note ?? null
  });
  if (error) throw error;
  return data;
}

export async function redeemBusinessActivation(code: string, organizationId: string) {
  const db = requireClient();
  const { data, error } = await db.rpc("redeem_activation_code", {
    p_code: code,
    p_organization_id: organizationId
  });
  if (error) throw error;
  return data;
}

export async function getPlatformOverview() {
  const db = requireClient();
  const { data, error } = await db.rpc("platform_admin_overview");
  if (error) throw error;
  return data;
}

export async function generateActivationCodes(planCode: string, quantity: number, expiresAt: string | null, note: string | null) {
  const db = requireClient();
  const { data, error } = await db.rpc("admin_generate_activation_codes", {
    p_plan_code: planCode,
    p_quantity: quantity,
    p_expires_at: expiresAt,
    p_note: note
  });
  if (error) throw error;
  return data;
}

export async function inviteEmployee(input: { organizationId: string; storeId: string; email: string; role: "manager" | "cashier" | "employee" }) {
  const db = requireClient();
  const { data: userData, error: userError } = await db.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("Sesi login tidak ditemukan.");
  const { data, error } = await db.from("employee_invites").insert({
    organization_id: input.organizationId,
    store_id: input.storeId,
    email: input.email.trim().toLowerCase(),
    role: input.role,
    invited_by: userData.user.id
  }).select("id,email,role,status").single();
  if (error) throw error;
  return data;
}

export async function markAttendance(input: { organizationId: string; storeId: string; existingId?: string | null }) {
  const db = requireClient();
  const { data: userData, error: userError } = await db.auth.getUser();
  if (userError) throw userError;
  if (!userData.user) throw new Error("Sesi login tidak ditemukan.");
  if (input.existingId) {
    const { error } = await db.from("attendance").update({ clock_out: new Date().toISOString() }).eq("id", input.existingId);
    if (error) throw error;
    return "clock_out";
  }
  const { error } = await db.from("attendance").insert({
    organization_id: input.organizationId,
    store_id: input.storeId,
    employee_user_id: userData.user.id,
    status: "present"
  });
  if (error) throw error;
  return "clock_in";
}

export async function createCustomer(input: { organizationId: string; storeId: string; fullName: string; phone: string; email?: string }) {
  const db = requireClient();
  const { data, error } = await db.from("customers").insert({
    organization_id: input.organizationId, store_id: input.storeId,
    full_name: input.fullName.trim(), phone: input.phone.trim() || null,
    email: input.email?.trim().toLowerCase() || null
  }).select("id,full_name,phone,email,member_code,points,store_id,created_at").single();
  if (error) throw error;
  return data;
}

export async function createCustomerTab(input: { organizationId: string; storeId: string; customerName: string; amount: number; dueDate?: string; note?: string }) {
  const db = requireClient();
  const { data: userData } = await db.auth.getUser();
  const { data, error } = await db.from("customer_tabs").insert({
    organization_id: input.organizationId, store_id: input.storeId,
    customer_name: input.customerName.trim(), amount: input.amount,
    due_date: input.dueDate || null, note: input.note || null,
    created_by: userData.user?.id
  }).select("id,customer_name,amount,paid_amount,due_date,status,created_at").single();
  if (error) throw error;
  return data;
}

export async function recordCustomerTabPayment(tabId: string, amount: number, method: string) {
  const db = requireClient();
  const { data, error } = await db.rpc("record_customer_tab_payment", {
    p_customer_tab_id: tabId, p_amount: amount, p_payment_method: method
  });
  if (error) throw error;
  return data;
}

export async function createReservation(input: { organizationId: string; storeId: string; customerName: string; phone: string; reservationAt: string; partySize: number; notes?: string }) {
  const db = requireClient();
  const { data: userData } = await db.auth.getUser();
  const { data, error } = await db.from("reservations").insert({
    organization_id: input.organizationId, store_id: input.storeId,
    customer_name: input.customerName.trim(), customer_phone: input.phone.trim() || null,
    reservation_at: input.reservationAt, party_size: input.partySize,
    notes: input.notes || null, created_by: userData.user?.id
  }).select("id,customer_name,customer_phone,reservation_at,party_size,status,notes").single();
  if (error) throw error;
  return data;
}

export async function updateReservationStatus(id: string, status: string) {
  const db = requireClient();
  const { error } = await db.from("reservations").update({ status }).eq("id", id);
  if (error) throw error;
}

export async function getPublicStoreCatalog(qrSlug: string) {
  const db = requireClient();
  const { data, error } = await db.rpc("get_public_store_catalog", { p_qr_slug: qrSlug });
  if (error) throw error;
  return data;
}

export async function submitPublicQrOrder(input: { qrSlug: string; customerName: string; note: string; items: { product_id: string; quantity: number }[] }) {
  const db = requireClient();
  const { data, error } = await db.rpc("submit_public_qr_order", {
    p_qr_slug: input.qrSlug,
    p_customer_name: input.customerName,
    p_customer_note: input.note || null,
    p_items: input.items,
    p_proof_image_path: null
  });
  if (error) throw error;
  return data;
}

export async function getPublicOrderQueue(qrSlug: string) {
  const db = requireClient();
  const { data, error } = await db.rpc("get_public_order_queue", { p_qr_slug: qrSlug });
  if (error) throw error;
  return data;
}

export async function createStore(input: { organizationId: string; name: string; address?: string; phone?: string }) {
  const db = requireClient();
  const code = "STORE-" + Math.random().toString(36).slice(2, 8).toUpperCase();
  const { data, error } = await db.from("stores").insert({
    organization_id: input.organizationId,
    name: input.name.trim(),
    code,
    address: input.address?.trim() || null,
    phone: input.phone?.trim() || null
  }).select("id,name,address,qr_slug,is_active").single();
  if (error) throw error;
  return data;
}

export async function reviewQrPayment(orderId: string, approved: boolean) {
  const db = requireClient();
  const { data, error } = await db.rpc("review_qr_payment", { p_order_id: orderId, p_approved: approved });
  if (error) throw error;
  return data;
}

export async function updateQrOrderStatus(orderId: string, status: "preparing" | "ready" | "completed" | "cancelled") {
  const db = requireClient();
  const { data, error } = await db.rpc("update_qr_order_status", { p_order_id: orderId, p_status: status });
  if (error) throw error;
  return data;
}

export async function assignEmployeeStore(input: { organizationId: string; userId: string; storeId: string | null }) {
  const db = requireClient();
  const { error } = await db.from("memberships").update({ store_id: input.storeId }).eq("organization_id", input.organizationId).eq("user_id", input.userId);
  if (error) throw error;
}

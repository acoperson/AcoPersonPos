# acoPos production checklist

## Supabase project
The project already contains the core multi-tenant schema and RLS. Do not apply a second organizations/stores schema. The new additive migrations are already applied to the connected project and mirrored in \`supabase/migrations\`.

- Existing tables include organizations, memberships, stores, products, store_inventory, sales, sale_items, shifts, attendance, schedules, QR orders, employee invites, business applications, subscriptions, and platform admins.
- New additions include one-time activation codes, customer/member records, kasbon and payment ledger, reservations, a privacy-safe public order queue, server-side branch-limit enforcement, and composite tenant foreign keys for store-scoped records.
- Review tenant isolation with at least two organizations and roles owner, admin, manager, cashier, and employee.
- Test concurrent POS checkout to confirm inventory cannot be oversold.
- Confirm the first platform administrator is explicitly registered in \`public.platform_admins\`.

## Authentication
- Disable **Confirm email** under Supabase Authentication → Providers → Email if the product must not require email verification.
- Set Site URL and redirect URLs for production and Netlify deploy previews.
- Test registration, login, logout, password recovery, employee invite claim, and session expiry.

## Netlify
- Build command: \`npm run build\`
- Publish directory: \`dist\`
- Ensure \`VITE_SUPABASE_URL\` and \`VITE_SUPABASE_PUBLISHABLE_KEY\` exist for production and deploy previews.
- Never add a Supabase service-role key to a \`VITE_\` variable or browser bundle.

## Manual package activation
- Admin creates codes through the admin-only \`admin_generate_activation_codes\` RPC.
- Codes are returned once and stored as hashes.
- Owners redeem with \`redeem_activation_code\`; code expiry, single-use status, role, and branch limits are checked server-side.
- Initial plan prices are provisional and must be confirmed before production marketing.

## Payments and hardware
- The POS checkout uses the existing atomic \`complete_pos_sale\` RPC.
- Public QR orders use the existing QR ordering RPCs.
- QRIS settlement and bank reconciliation need payment-provider configuration and verified server-side webhooks.
- Thermal printing and dedicated customer/TV displays require device/browser testing before being considered production-ready.

## Release verification
- Run \`npm run build\` in CI.
- Test owner onboarding and Free Store creation.
- Test branch limits after each plan activation.
- Test product creation, stock adjustments, POS checkout, void/refund policy, and receipt generation.
- Test employee invites and store-scoped access.
- Test customer/member, kasbon payments, and reservation workflows.
- Test QR ordering, payment confirmation, rejected-payment stock restoration, and public order queue visibility.
- Test mobile layouts, keyboard accessibility, and reduced-motion behavior.

# acoPos

Dark Premium business management and point-of-sale platform.

## Stack
- Vite + React 19 + TypeScript
- Supabase Auth + PostgreSQL + Row Level Security
- Lucide icons
- Netlify hosting

## Run locally
1. Install Node.js 20.19+ or 22.12+.
2. Run \`npm install\`.
3. Copy \`.env.example\` to \`.env.local\` and add the Supabase project URL and publishable key.
4. Run \`npm run dev\`.
5. Run \`npm run build\` to create the production bundle.

## Existing backend
This repository connects to the existing acoPos Supabase schema. It does not replace the existing organizations, memberships, stores, products, inventory, sales, shifts, QR orders, employee invites, business applications, or platform-admin tables.

The frontend uses the existing tenant-aware RPCs and RLS policies:
- \`submit_business_application\` for initial Free Store setup.
- \`claim_employee_invites\` for matching email invitations after sign-in.
- \`open_cashier_shift\` and \`complete_pos_sale\` for atomic cashier operations and inventory decrement.
- \`get_public_store_catalog\` and \`submit_public_qr_order\` for public QR ordering.
- \`platform_admin_overview\` and \`review_business_application\` for platform administration.

## Additive database migrations
The existing Supabase migrations from 2026-11-08 remain intact. New additive migrations are mirrored in \`supabase/migrations\`:
- \`20261109145512_acopos_manual_activation_codes.sql\`: manual one-time activation codes, plan duration and branch limits.
- \`20261109145941_acopos_customers_reservations_tabs_branch_limits.sql\`: customer/member records, reservations, kasbon, payment ledger, and branch-limit enforcement.
- \`20261109145951_acopos_harden_customer_tab_payment_permissions.sql\`: restricts direct kasbon-payment writes so payments go through the atomic RPC.

These migrations have been applied to the connected acoPos Supabase project. Do not re-create a second tenant schema.

## Authentication and first-time setup
- Supabase Auth uses email/password.
- To meet the product requirement of no mandatory email verification, turn OFF **Authentication → Providers → Email → Confirm email** in the Supabase project settings.
- Set the Site URL and redirect URLs for the production domain and Netlify deploy previews.
- A newly registered owner creates a Free Store business from the onboarding screen.
- Platform administrators must be explicitly added to \`public.platform_admins\` by an existing trusted project administrator. Do not expose service-role credentials in the browser.

## Activation policy
Paid plans are not auto-billed. An authorized platform admin generates one-time activation codes; an owner redeems a code for their organization. Codes are stored as SHA-256 hashes and can be redeemed only once. The initial plan prices in the migration are draft values and can be changed in \`subscription_plans\`.

## Netlify
- Build command: \`npm run build\`
- Publish directory: \`dist\`
- Netlify already has \`VITE_SUPABASE_URL\` and \`VITE_SUPABASE_PUBLISHABLE_KEY\` configured for deploy contexts.

## Integrations still requiring provider/device configuration
Actual QRIS settlement, payment-provider webhooks, thermal-printer drivers, and production TV/customer-display hardware should be configured and tested with the chosen provider and devices before being advertised as live.

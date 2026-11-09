# acoPos production setup checklist

The feature branch contains a working front-end demo and the first database migrations. Complete these steps before storing real customer or business data.

## 1. Supabase project
- Create a Supabase project in the appropriate region.
- Run migrations in order:
  1. \`202611090001_initial_schema.sql\`
  2. \`202611090002_signup_bootstrap.sql\`
- Configure the project URL and publishable key in the app environment.
- In Authentication > Providers > Email, disable "Confirm email" if the product policy is to allow registration without mandatory email verification.
- Set the correct site URL and redirect URLs for \`https://acopos.my.id\` and the Netlify deploy preview host.
- Review RLS policies with owner, manager, cashier, and cross-business test accounts.

## 2. Netlify
Set these environment variables for production and deploy previews:
- \`VITE_SUPABASE_URL\`
- \`VITE_SUPABASE_PUBLISHABLE_KEY\`

Build settings:
- Build command: \`npm run build\`
- Publish directory: \`dist\`

## 3. Platform administration
The public client must never receive the Supabase service-role key. Implement trusted Edge Functions or server endpoints for:
- Admin-only activation code generation.
- One-time activation code validation and redemption.
- Staff invitation and branch assignment.
- Any privileged platform-wide support or moderation action.

Activation code values should be generated with cryptographically secure randomness and stored as hashes. Redemption must run transactionally and verify expiry, status, plan limits, and business ownership.

## 4. Payments and hardware
The interface includes payment-method selection and QRIS configuration placeholders. Before enabling actual payments, integrate a licensed payment provider and verify webhook signatures server-side. Printer, customer display, and TV queue output need device/browser testing and a hardware integration strategy.

## 5. Release verification
- Run \`npm run build\`.
- Test registration, login, logout, password reset, and auth redirects.
- Test tenant isolation with at least two separate businesses.
- Test role permissions for ADMIN, OWNER BISNIS, MANAJER, and KARYAWAN.
- Test branch and package limits server-side.
- Test POS stock deduction, refunds/cancellations, and order consistency with concurrent cashiers.
- Test QR ordering and all payment settlement states.
- Test mobile layouts and keyboard accessibility.

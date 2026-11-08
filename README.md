# ACOPOS

ACOPOS is a multi-store business operations platform: POS, inventory, QR ordering, employee attendance, shifts, and reporting.

## Stack
- React + TypeScript + Vite
- Supabase Auth, Postgres, and Storage
- Netlify hosting

## Local development
1. Install Node.js 20.19+.
2. Run `npm install`.
3. Copy `.env.example` to `.env` and fill the Supabase project URL and publishable key.
4. Run `npm run dev`.

## Authentication
Email OTP is used. The frontend calls `signInWithOtp` and `verifyOtp` with `type: "email"`. Configure Supabase Auth email OTP templates to render `{{ .Token }}` and confirm the six-digit OTP settings before production testing.

## Security
Never put Supabase secret/service-role keys or Resend SMTP credentials in frontend variables. Database access must be protected by RLS.

## Required Supabase configuration

- Set the Netlify build variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` for production, deploy previews, and branch deploys.
- These are public browser configuration values. Never put a Supabase secret/service-role key or Resend API key in a `VITE_*` variable.
- Configure Supabase Auth email delivery with the verified sender domain in Resend (SMTP host `smtp.resend.com`, port `465` or `587`, username `resend`, password = Resend API key). Store the SMTP credential only in Supabase Auth SMTP settings.
- Configure the Supabase email OTP template to render `{{ .Token }}`; set the email OTP length to six digits and verify the expiry/rate limits before launch.
- Keep password recovery redirect URLs and the ACOPOS production/preview URLs in the Supabase Auth URL allow list.

## Release checklist

1. Review the open ACOPOS platform pull request and its CI checks.
2. Apply the pending migrations in timestamp order only after reviewing the SQL against the target Supabase project:
   - `20261108231500_platform_and_shift_workflows.sql`
   - `20261109000100_fix_public_qr_payment_proof_storage_policies.sql`
3. Verify Supabase migration history includes both versions and rerun the Database Linter.
4. Test signup, password login, six-digit OTP, password reset, and employee invite acceptance with dedicated test accounts.
5. Test the three business rules: Free activates immediately; a new Business application waits for Platform Owner approval; Free-to-Business upgrade waits for approval while Free remains usable.
6. Test POS checkout/stock movements, cashier open/close shift, QR ordering, optional proof upload, manual payment approval/rejection, order status transitions, and CSV reporting.
7. Verify a Netlify Deploy Preview before merging or publishing to the production domain.

## Local verification

```bash
npm install
npx tsc --noEmit
npm run build
```

The current CI workflow runs the TypeScript check and production build on the development branch. A successful build does not replace the end-to-end checks in the release checklist.

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
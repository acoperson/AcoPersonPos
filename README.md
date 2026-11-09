# acoPos

Dark Premium business management and point-of-sale workspace.

## Stack
- Vite + React 19 + TypeScript
- Supabase Auth + PostgreSQL (optional until environment variables are configured)
- Lucide icons
- Netlify static hosting

## Run locally
1. Install Node.js 20.19+ or 22.12+.
2. Run \`npm install\`.
3. Copy \`.env.example\` to \`.env.local\` and add your Supabase project URL and publishable key.
4. Run \`npm run dev\`.
5. Run \`npm run build\` to create the production bundle.

## Current implementation
- Responsive public landing page and pricing presentation.
- Login and registration UI, with Supabase password auth when configured.
- Business workspace navigation and dashboard.
- POS cart, product creation, stock decrement, and local demo order history.
- Products, orders, branches, employees, reports, QR menu, members, settings, and activation-code screens.
- Local demo data is stored in browser localStorage when Supabase is not configured.

## Important deployment notes
The UI has a local demo mode so the screens can be explored without credentials. Local demo data is not shared between devices and is not a production database. Configure Supabase and apply the SQL migration in \`supabase/migrations/202611090001_initial_schema.sql\` before using real business data.

The production database migration establishes tenant-scoped tables and row-level security. Before enabling public signups, configure Supabase Auth redirect URLs and review the policies for your exact operating model. Payment providers, QRIS settlement, thermal printer drivers, and real-time TV/customer displays require provider credentials and device-specific integration; this repository does not pretend those integrations are live.

## Netlify
Build command: \`npm run build\`
Publish directory: \`dist\`
Add \`VITE_SUPABASE_URL\` and \`VITE_SUPABASE_PUBLISHABLE_KEY\` as Netlify environment variables after creating the Supabase project.

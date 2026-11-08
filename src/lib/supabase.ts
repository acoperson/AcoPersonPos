import { createClient } from "@supabase/supabase-js";
const rawUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
// Accept either the project root URL or an accidentally pasted /rest/v1 endpoint.
const url = rawUrl?.replace(/\/rest\/v1\/?$/, "");
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
export const isSupabaseConfigured = Boolean(url && key);
export const supabase = isSupabaseConfigured ? createClient(url!, key!) : null;
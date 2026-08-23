import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

export const isSupabaseConfigured = Boolean(url && publishableKey);
export const supabase = isSupabaseConfigured ? createClient(url!, publishableKey!) : null;

export async function lookupCustomerByPhone(phone: string) {
  if (!supabase) return { data: null, error: new Error('Supabase is not configured') };
  return supabase.rpc('lookup_customer_by_phone', { p_phone: phone });
}

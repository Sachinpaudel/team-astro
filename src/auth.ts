import type { SupabaseClient } from '@supabase/supabase-js';

export type SignupRole = 'business' | 'customer';

export class AuthService {
  constructor(private readonly db: SupabaseClient) {}

  signUp(email: string, password: string, role: SignupRole, fullName: string) {
    return this.db.auth.signUp({
      email,
      password,
      options: { data: { role, full_name: fullName } },
    });
  }

  signIn(email: string, password: string) {
    return this.db.auth.signInWithPassword({ email, password });
  }

  signOut() {
    return this.db.auth.signOut();
  }

  getSession() {
    return this.db.auth.getSession();
  }

  async getMyRole() {
    const { data: userData, error: userError } = await this.db.auth.getUser();
    if (userError) throw userError;
    if (!userData.user) return null;
    const { data, error } = await this.db
      .from('users')
      .select('role, status')
      .eq('id', userData.user.id)
      .single();
    if (error) throw error;
    return data as { role: 'business' | 'customer' | 'admin' | 'ird_officer'; status: string };
  }
}

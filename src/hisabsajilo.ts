import type { SupabaseClient } from '@supabase/supabase-js';

export interface InvoiceItemInput {
  description: string;
  category?: string;
  quantity: number;
  unit_price: number;
}

export interface CreateInvoiceInput {
  customerId: string;
  dueDate: string;
  paymentMethod?: 'cash' | 'online';
  notes?: string;
  items: InvoiceItemInput[];
}

export type NegotiationAction = 'accept' | 'reject' | 'counter';

export class HisabSajiloService {
  constructor(private readonly db: SupabaseClient) {}

  private async currentUserId() {
    const { data, error } = await this.db.auth.getUser();
    if (error) throw error;
    if (!data.user) throw new Error('Authentication is required');
    return data.user.id;
  }

  async createInvoice(input: CreateInvoiceInput) {
    const businessId = await this.currentUserId();
    const amount = input.items.reduce((total, item) => total + item.quantity * item.unit_price, 0);
    const description = input.items.map(item => `${item.description} × ${item.quantity}`).join('\n');
    return this.db.from('invoices').insert({
      customer_id: input.customerId,
      business_id: businessId,
      fiscal_year_code: '2083/084',
      amount_before_vat: amount,
      description,
      payment_due_at: input.dueDate,
      payment_method: input.paymentMethod ?? 'online',
      status: 'pending_agreement',
      awaiting_response_from: 'customer',
    }).select().single();
  }

  respondToInvoice(invoiceId: string, action: NegotiationAction, amount?: number, note?: string) {
    return this.db.rpc('respond_to_invoice', {
      p_invoice_id: invoiceId,
      p_action: action,
      p_amount: amount ?? null,
      p_note: note ?? null,
    });
  }

  markWorkCompleted(invoiceId: string) {
    return this.db.rpc('mark_work_completed', { p_invoice_id: invoiceId });
  }

  async uploadPaymentScreenshot(invoiceId: string, file: File) {
    const extension = file.name.split('.').pop()?.toLowerCase() || 'jpg';
    const path = `${invoiceId}/${crypto.randomUUID()}.${extension}`;
    const { error } = await this.db.storage.from('payment-screenshots').upload(path, file, { contentType: file.type, upsert: false });
    if (error) throw error;
    return path;
  }

  markPaid(invoiceId: string, paymentMethod: 'cash' | 'online', proofUrl?: string, remarks?: string) {
    return this.db.rpc('mark_payment_paid', {
      p_invoice_id: invoiceId,
      p_payment_method: paymentMethod,
      p_payment_screenshot_url: proofUrl ?? null,
      p_remarks: remarks ?? null,
    });
  }

  verifyPayment(invoiceId: string, remarks?: string) {
    return this.db.rpc('verify_payment', { p_invoice_id: invoiceId, p_remarks: remarks ?? null });
  }

  rejectPayment(invoiceId: string, remarks: string) {
    return this.db.rpc('reject_payment', { p_invoice_id: invoiceId, p_remarks: remarks });
  }

  paymentScreenshotUrl(path: string) {
    return this.db.storage.from('payment-screenshots').createSignedUrl(path, 300);
  }

  listMyInvoices() {
    return this.db.from('invoices').select('*').order('created_at', { ascending: false });
  }

  listMyBills() {
    return this.db.from('bills').select('*').order('bill_date', { ascending: false });
  }

  async createSupportTicket(subject: string, priority: 'low' | 'normal' | 'high' | 'urgent' = 'normal', relatedInvoiceId?: string) {
    const userId = await this.currentUserId();
    return this.db.from('support_tickets').insert({
      created_by_user_id: userId,
      subject,
      priority,
      related_invoice_id: relatedInvoiceId ?? null,
    }).select().single();
  }

  async reportInvoice(invoiceId: string, reason: string, description?: string) {
    const userId = await this.currentUserId();
    return this.db.from('flagged_invoices').insert({
      invoice_id: invoiceId,
      reported_by_user_id: userId,
      reason,
      description: description ?? null,
    }).select().single();
  }
}

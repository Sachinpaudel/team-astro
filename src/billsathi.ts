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
  paymentMethod?: string;
  notes?: string;
  items: InvoiceItemInput[];
}

export class BillSathiService {
  constructor(private readonly db: SupabaseClient) {}

  createInvoice(input: CreateInvoiceInput) {
    return this.db.rpc('create_invoice', {
      p_customer_id: input.customerId,
      p_due_date: input.dueDate,
      p_items: input.items,
      // PostgreSQL derives VAT from the admin-verified business tax profile.
      p_vat_rate: 0,
      p_payment_method: input.paymentMethod ?? 'fonepay_qr',
      p_notes: input.notes ?? null,
    });
  }

  markPaid(invoiceId: string, reference?: string, proofPath?: string, note?: string) {
    return this.db.rpc('mark_invoice_paid', {
      p_invoice_id: invoiceId,
      p_reference: reference ?? null,
      p_proof_path: proofPath ?? null,
      p_note: note ?? null,
    });
  }

  reviewPayment(paymentId: string, confirmed: boolean, note?: string) {
    return this.db.rpc('review_payment', {
      p_payment_id: paymentId,
      p_confirmed: confirmed,
      p_note: note ?? null,
    });
  }

  businessDashboard(businessId: string) {
    return this.db.rpc('business_dashboard', { p_business_id: businessId });
  }

  customerDashboard(customerId: string) {
    return this.db.rpc('customer_dashboard', { p_customer_id: customerId });
  }
}

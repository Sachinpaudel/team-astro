export type Status = 'Paid' | 'Pending' | 'Overdue' | 'Rejected' | 'Verified' | 'Flagged';

export const businessInvoices = [
  { id: 'INV-2025-001', customer: 'Kathmandu Repair Hub', date: 'Aug 12, 2025', amount: 'NPR 1,25,000', status: 'Pending' as Status },
  { id: 'INV-2025-002', customer: 'Himalayan Merchants', date: 'Aug 10, 2025', amount: 'NPR 45,000', status: 'Paid' as Status },
  { id: 'INV-2025-003', customer: 'Everest Logistics', date: 'Aug 08, 2025', amount: 'NPR 1,50,000', status: 'Overdue' as Status },
  { id: 'INV-2025-004', customer: 'Kiran Enterprises', date: 'Aug 03, 2025', amount: 'NPR 1,05,000', status: 'Rejected' as Status },
];

export const customerInvoices = [
  { id: 'INV-2025-034', customer: 'TechNova Solutions', date: 'Oct 08, 2025', amount: 'NPR 15,000', status: 'Pending' as Status },
  { id: 'INV-2025-031', customer: 'Himalayan Legal', date: 'Oct 04, 2025', amount: 'NPR 8,500', status: 'Paid' as Status },
  { id: 'INV-2025-028', customer: 'Everest Marketing', date: 'Sep 30, 2025', amount: 'NPR 21,200', status: 'Overdue' as Status },
  { id: 'INV-2025-022', customer: 'Kathmandu Consultants', date: 'Sep 18, 2025', amount: 'NPR 12,500', status: 'Paid' as Status },
];

export const businesses = [
  { name: 'Everest Tech Solutions', type: 'IT Services', rating: '4.8', price: 'NPR 12,000', distance: '0.8 km', verified: true },
  { name: 'Kathmandu Legal', type: 'Legal Services', rating: '4.7', price: 'NPR 8,500', distance: '1.2 km', verified: true },
  { name: 'Apex Financial Audit', type: 'Audit & Tax', rating: '4.9', price: 'NPR 15,000', distance: '1.8 km', verified: true },
  { name: 'Himalayan Repairs', type: 'Repair Service', rating: '4.6', price: 'NPR 3,500', distance: '2.1 km', verified: false },
];

export const customers = [
  { name: 'Apex Tech Pvt. Ltd.', contact: 'Sagar Gurung', pan: '302145678', total: 'NPR 1,25,000', invoices: 12, status: 'Active' },
  { name: 'Bikash Sharma', contact: 'Individual', pan: '—', total: 'NPR 45,000', invoices: 5, status: 'Active' },
  { name: 'Chaudhary Electronics', contact: 'Corporate', pan: '601249830', total: 'NPR 95,000', invoices: 8, status: 'Pending' },
];

export const verification = [
  { entity: 'Himalayan Traders Pvt. Ltd.', type: 'Business', date: '2025-08-12', pan: '301457889', status: 'Pending Review' },
  { entity: 'Anita Sharma', type: 'Individual', date: '2025-08-10', pan: '—', status: 'Pending KYC' },
  { entity: 'Kathmandu Logistics', type: 'Business', date: '2025-08-09', pan: '600425113', status: 'Flagged Docs' },
  { entity: 'Everest Tech Solutions', type: 'Business', date: '2025-08-06', pan: '302145678', status: 'Pending Review' },
];

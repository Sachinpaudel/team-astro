import type { Status } from './data.js';

interface DownloadInvoice {
  id: string;
  seller: string;
  buyer: string;
  date: string;
  status: Status | string;
  subtotal: number;
  vat: number;
  total: number;
  vatRegistered: boolean;
}

export async function downloadInvoicePdf(invoice: DownloadInvoice) {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const blue: [number,number,number] = [20,117,200];
  doc.setFillColor(...blue); doc.rect(0,0,210,7,'F');
  doc.setTextColor(...blue); doc.setFontSize(18); doc.setFont('helvetica','bold');
  doc.text(invoice.vatRegistered ? 'TAX INVOICE' : 'SALES INVOICE', 105, 20, { align:'center' });
  doc.setFontSize(9); doc.setTextColor(90,105,122);
  doc.text(invoice.vatRegistered ? 'VAT taxable supply - Nepal' : 'Non-VAT registered seller',105,26,{align:'center'});

  doc.setFontSize(15); doc.setTextColor(25,36,50); doc.text(invoice.seller,15,40);
  doc.setFontSize(9); doc.setFont('helvetica','normal'); doc.setTextColor(85,99,116);
  doc.text('New Baneshwor, Kathmandu, Nepal',15,46);
  doc.text('PAN: 302145678',15,51);
  if(invoice.vatRegistered) doc.text('VAT No: 302145678',15,56);
  doc.setTextColor(25,36,50); doc.setFont('helvetica','bold'); doc.text(invoice.id,195,40,{align:'right'});
  doc.setFont('helvetica','normal'); doc.setTextColor(85,99,116); doc.text(`Invoice date: ${invoice.date}`,195,46,{align:'right'}); doc.text(`Status: ${invoice.status}`,195,51,{align:'right'});

  doc.setDrawColor(220,227,235); doc.line(15,65,195,65);
  doc.setFont('helvetica','bold'); doc.setTextColor(20,117,200); doc.text('BILL TO',15,73);
  doc.setTextColor(25,36,50); doc.setFontSize(11); doc.text(invoice.buyer,15,80);
  doc.setFontSize(9); doc.setFont('helvetica','normal'); doc.setTextColor(85,99,116); doc.text('Kathmandu, Nepal',15,86);

  const y=98; doc.setFillColor(242,247,252); doc.rect(15,y,180,10,'F');
  doc.setTextColor(55,73,93); doc.setFont('helvetica','bold');
  doc.text('S.N.',18,y+6); doc.text('PARTICULARS',32,y+6); doc.text('QTY',135,y+6); doc.text('RATE',155,y+6); doc.text('AMOUNT',193,y+6,{align:'right'});
  doc.setFont('helvetica','normal'); doc.setTextColor(40,52,67); doc.text('1',18,y+18); doc.text('Professional service charge',32,y+18); doc.text('1',135,y+18); doc.text(`NPR ${invoice.subtotal.toLocaleString()}`,155,y+18); doc.text(`NPR ${invoice.subtotal.toLocaleString()}`,193,y+18,{align:'right'});
  doc.setDrawColor(225,231,238); doc.line(15,y+23,195,y+23);

  let ty=y+35; doc.text('Subtotal',145,ty); doc.setFont('helvetica','bold'); doc.text(`NPR ${invoice.subtotal.toLocaleString()}`,193,ty,{align:'right'});
  if(invoice.vatRegistered){ty+=8;doc.setFont('helvetica','normal');doc.text('VAT @ 13%',145,ty);doc.setFont('helvetica','bold');doc.text(`NPR ${invoice.vat.toLocaleString()}`,193,ty,{align:'right'});}
  ty+=10;doc.setDrawColor(20,117,200);doc.line(142,ty-6,195,ty-6);doc.setFontSize(12);doc.setTextColor(...blue);doc.text('GRAND TOTAL',142,ty);doc.text(`NPR ${invoice.total.toLocaleString()}`,193,ty,{align:'right'});

  doc.setFontSize(9); doc.setTextColor(70,84,100); doc.setFont('helvetica','normal');
  doc.text('Amount in words: Fifteen thousand rupees only',15,165);
  doc.text('Payment method: Fonepay QR / Bank transfer',15,174);
  doc.line(145,188,195,188); doc.text('Authorized signature',170,194,{align:'center'});
  doc.setFillColor(246,248,251); doc.rect(15,210,180,18,'F'); doc.setFontSize(8);
  const note=invoice.vatRegistered?'VAT is charged because the seller is VAT registered. Prototype document - not IRD certified.':'VAT is not charged and no VAT number is displayed because the seller is not VAT registered.';
  doc.text(doc.splitTextToSize(note,170),20,219);
  doc.setFillColor(...blue);doc.rect(0,290,210,7,'F');
  doc.save(`${invoice.id}-${invoice.vatRegistered?'tax-invoice':'invoice'}.pdf`);
}

export function downloadStatementCsv(rows: Array<{id:string;customer:string;date:string;amount:string;status:string}>, filename: string) {
  const csv=['Invoice ID,Provider/Customer,Date,Amount,Status',...rows.map(r=>[r.id,r.customer,r.date,r.amount,r.status].map(v=>`"${String(v).replaceAll('"','""')}"`).join(','))].join('\n');
  const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));
  const link=document.createElement('a');link.href=url;link.download=filename;link.click();URL.revokeObjectURL(url);
}

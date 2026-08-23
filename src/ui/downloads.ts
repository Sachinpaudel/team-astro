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
  paymentMethod: 'Cash' | 'Online';
}

export async function downloadInvoicePdf(invoice: DownloadInvoice) {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const left=15, right=195, width=180; doc.setTextColor(28,28,28); doc.setDrawColor(30,30,30);
  doc.setFont('helvetica','normal');doc.setFontSize(12);doc.text(invoice.vatRegistered?'TAX INVOICE':'BILL',105,16,{align:'center'});
  doc.roundedRect(left,21,width,31,1,1);
  doc.setFont('helvetica','bold');doc.setFontSize(20);doc.text(invoice.seller,105,33,{align:'center'});
  doc.setFont('helvetica','normal');doc.setFontSize(10);doc.text('New Baneshwor, Kathmandu',105,40,{align:'center'});doc.text('Ph: +977-9800000000',105,46,{align:'center'});
  if(invoice.vatRegistered){doc.setFontSize(11);doc.text('VAT No: 302145678',190,29,{align:'right'});}
  doc.setFontSize(10); const billNo=`083/84-${invoice.id.slice(-6)}`;
  doc.text("Buyer's Name",left,64);doc.text(`: ${invoice.buyer}`,47,64);doc.text('Bill No.',108,64);doc.text(`: ${billNo}`,140,64);
  doc.text("Buyer's Address",left,72);doc.text(': Kathmandu',47,72);doc.text('Bill Date',108,72);doc.text(': 2083-05-01',140,72);
  doc.text('Mode',left,80);doc.text(`: ${invoice.paymentMethod}`,47,80);
  const y=92;doc.setFillColor(242,242,242);doc.rect(left,y,width,9,'FD');doc.line(34,y,34,y+22);doc.line(160,y,160,y+22);doc.setFont('helvetica','bold');doc.text('SNo',18,y+6);doc.text('Particulars',37,y+6);doc.text('Amount',190,y+6,{align:'right'});
  doc.setFont('helvetica','normal');doc.rect(left,y+9,width,13);doc.text('1',18,y+17);doc.text('Professional service charge - as agreed',37,y+17);doc.text(invoice.subtotal.toLocaleString(undefined,{minimumFractionDigits:2}),190,y+17,{align:'right'});
  const boxY=y+22, boxH=invoice.vatRegistered?37:24;doc.rect(left,boxY,98,boxH);doc.setFont('helvetica','bold');doc.text('Amount in words:',18,boxY+8);doc.setFont('helvetica','normal');doc.text(doc.splitTextToSize('(Rs. Fifteen Thousand only)',88),18,boxY+16);
  doc.rect(117,boxY,78,boxH);doc.line(145,boxY,145,boxY+boxH);let rowY=boxY;
  const summary:[string,number][]=[['Sub Total',invoice.subtotal]];if(invoice.vatRegistered){summary.push(['Taxable Amt.',invoice.subtotal],['VAT @ 13%',invoice.vat])}summary.push(['Grand Total',invoice.total]);
  const rowH=boxH/summary.length;summary.forEach(([label,value],i)=>{if(i)doc.line(117,rowY,195,rowY);doc.setFont('helvetica',i===summary.length-1?'bold':'normal');doc.text(label,120,rowY+rowH*.65);doc.text(value.toLocaleString(undefined,{minimumFractionDigits:2}),190,rowY+rowH*.65,{align:'right'});rowY+=rowH});
  const footerY=boxY+boxH+18;doc.setFont('helvetica','normal');doc.text('E. & O.E.',left,footerY);doc.text('Thank you.',left,footerY+7);doc.line(148,footerY-2,195,footerY-2);doc.text(invoice.seller,171.5,footerY+5,{align:'center'});doc.setFontSize(8);doc.text(`For, ${invoice.seller}`,171.5,footerY+11,{align:'center'});
  doc.setFontSize(9);doc.text(`Bill #${billNo} - generated electronically, no physical signature required.`,left,footerY+24);
  doc.save(`${invoice.id}-${invoice.vatRegistered?'tax-invoice':'invoice'}.pdf`);
}

export function downloadStatementCsv(rows: Array<{id:string;customer:string;date:string;amount:string;status:string}>, filename: string) {
  const csv=['Invoice ID,Provider/Customer,Date,Amount,Status',...rows.map(r=>[r.id,r.customer,r.date,r.amount,r.status].map(v=>`"${String(v).replaceAll('"','""')}"`).join(','))].join('\n');
  const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));
  const link=document.createElement('a');link.href=url;link.download=filename;link.click();URL.revokeObjectURL(url);
}

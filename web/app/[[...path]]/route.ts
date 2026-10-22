import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
const pages = new Set(['index.html','dashboard.html','reports/attendance.html','reports/working-hours.html','reports/project-utilization.html','reports/project-billing.html','reports/clients.html','reports/billing-status.html']);
export async function GET(_request: Request, context: {params: Promise<{path?: string[]}>}) {
  const {path} = await context.params;
  const name = path?.join('/') || 'index.html';
  if (!pages.has(name)) return new Response('Not found', {status:404});
  let html = await readFile(join(process.cwd(),'legacy',name),'utf8');
  if(name==='reports/project-billing.html' || name==='reports/project-utilization.html'){
    html=html.replace('</body>','<script src="../assets/js/files.js"></script></body>');
  }
  return new Response(html, {headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'same-origin'}});
}

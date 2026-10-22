interface SessionIdentity {token: string;userId: number;employeeCode: string;name: string;role: string}
interface ApiOptions {method?: string;body?: unknown;auth?: boolean}
interface ApiEnvelope {success: boolean;message: string;data: unknown}
interface Window {
  APP_CONFIG: {API_BASE_URL: string};
  ROOT?: string;
  api: {get(path: string): Promise<unknown>;post(path: string,body: unknown,options?: ApiOptions): Promise<unknown>;delete(path: string): Promise<unknown>};
}

// The preserved UI consumes this envelope; all business operations stay in FastAPI.
(() => {
  function token(): string | null {
    try {return (JSON.parse(sessionStorage.getItem('session') || 'null') as SessionIdentity | null)?.token || null;}
    catch {return null;}
  }
  async function request(path: string,options: ApiOptions={}): Promise<unknown> {
    const headers: Record<string,string>={'Content-Type':'application/json'};
    if(options.auth!==false){const value=token();if(value)headers.Authorization=`Bearer ${value}`;}
    let response: Response;
    try {
      response=await fetch(window.APP_CONFIG.API_BASE_URL+path,{method:options.method||'GET',headers,body:options.body===undefined?undefined:JSON.stringify(options.body)});
    } catch {throw new Error('Cannot reach the backend. Is it running?');}
    if(response.status===401 && options.auth!==false){
      sessionStorage.removeItem('session');
      window.location.href=(window.ROOT||'.')+'/index.html';
      throw new Error('Session expired');
    }
    let payload: ApiEnvelope | null=null;
    try {payload=await response.json() as ApiEnvelope;}catch {}
    if(!response.ok||!payload||payload.success===false)throw new Error(payload?.message||`Request failed (${response.status})`);
    return payload.data;
  }
  window.api={get:path=>request(path),post:(path,body,options)=>request(path,{method:'POST',body,...options}),delete:path=>request(path,{method:'DELETE'})};
})();

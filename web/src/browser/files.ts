// Additive attachment control using the preserved report CSS and dialog chrome.
// All identity/authorization calls go through FastAPI; R2 gets only a signed URL.
(() => {
  type FileRow={id:string;name:string;size:number;contentType:string};
  type Grant={id:string;url:string;headers:Record<string,string>};
  const target=new URLSearchParams(location.search).get('project');
  const app=document.getElementById('app');
  if(!target || !/^\d+$/.test(target) || !app)return;
  let session:SessionIdentity|null=null;
  try{session=JSON.parse(sessionStorage.getItem('session')||'null') as SessionIdentity|null;}catch{}
  if(!session || !['CAPTAIN','PROJECT_CONTROLLER'].includes(session.role))return;
  const make=<T extends keyof HTMLElementTagNameMap>(tag:T,text?:string)=>{
    const node=document.createElement(tag);if(text)node.textContent=text;return node;
  };
  async function openFiles(){
    const dialog=make('dialog');dialog.className='month-picker';
    const title=make('h3','Attachments'),status=make('p'),list=make('div');status.setAttribute('role','status');
    const category=make('select');category.setAttribute('aria-label','Attachment category');
    for(const [key,label] of [['project_attachment','Project attachments'],['billing_document','Billing documents']]){
      const option=make('option',label);option.value=key;category.append(option);
    }
    const input=make('input');input.type='file';input.accept='.pdf,.jpg,.jpeg,.png,.xlsx';input.setAttribute('aria-label','Choose attachment');
    const progress=make('progress');progress.max=1;progress.hidden=true;
    const close=make('button','Close');close.onclick=()=>dialog.close();
    let busy=false;
    const controls=(value:boolean)=>{busy=value;input.disabled=value;category.disabled=value;close.disabled=value;};
    const failed=(error:unknown)=>{status.textContent=error instanceof Error?error.message:'File operation failed';};
    async function load(){
      list.replaceChildren();status.textContent='Loading attachments…';
      try{
        let cursor:string|undefined;let count=0;
        do{
          const rows=await window.api.get(`/api/files?category=${category.value}&targetId=${target}&limit=100${cursor?'&after='+cursor:''}`) as FileRow[];
          for(const row of rows){
            count++;
            const card=make('div');card.className='card';card.append(make('p',`${row.name} · ${row.size} bytes`));
            const download=make('button','Download'),remove=make('button','Delete');
            async function fetchObject(){
              const grant=await window.api.get('/api/files/'+row.id+'/download') as Grant;
              const response=await fetch(grant.url,{headers:grant.headers,credentials:'omit',redirect:'error'});
              if(!response.ok)throw new Error('Download failed. Try again for a fresh download link.');
              return response.blob();
            }
            download.onclick=async()=>{
              if(busy)return;controls(true);
              try{
                const blob=await fetchObject(),url=URL.createObjectURL(blob),link=make('a');link.href=url;link.download=row.name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
                status.textContent='Download ready';
              }catch(error){failed(error);}finally{controls(false);}
            };
            remove.onclick=async()=>{
              if(busy || !confirm(`Delete "${row.name}"?`))return;controls(true);
              try{await window.api.delete('/api/files/'+row.id);await load();}catch(error){failed(error);}finally{controls(false);}
            };
            card.append(download,remove);
            if(row.contentType.startsWith('image/')){
              const preview=make('button','Preview');preview.onclick=async()=>{
                if(busy)return;controls(true);
                try{
                  const blob=await fetchObject(),url=URL.createObjectURL(blob),image=make('img');image.src=url;image.alt=row.name;image.style.maxWidth='100%';
                  const previewDialog=make('dialog');previewDialog.className='month-picker';const done=make('button','Close preview');done.onclick=()=>previewDialog.close();
                  previewDialog.append(image,done);previewDialog.onclose=()=>{URL.revokeObjectURL(url);previewDialog.remove();};document.body.append(previewDialog);previewDialog.showModal();
                }catch(error){failed(error);}finally{controls(false);}
              };card.append(preview);
            }
            list.append(card);
          }
          cursor=rows.length===100?rows[rows.length-1].id:undefined;
        }while(cursor);
        status.textContent=count?'':'No attachments yet';
      }catch(error){failed(error);const retry=make('button','Retry');retry.onclick=()=>{void load();};list.append(retry);}
    }
    input.onchange=async()=>{
      const file=input.files?.[0];if(!file || busy)return;
      if(!file.size || file.size>10*1024*1024){status.textContent='Choose a file up to 10 MB';return;}
      const types:Record<string,string>={pdf:'application/pdf',jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'};
      const type=types[file.name.split('.').pop()?.toLowerCase()||''];if(!type){status.textContent='Unsupported file type';return;}
      controls(true);progress.hidden=false;progress.value=0;status.textContent='Uploading…';let id:string|undefined;
      try{
        const grant=await window.api.post('/api/files/authorize-upload',{name:file.name,size:file.size,contentType:type,category:category.value,targetId:Number(target)}) as Grant;id=grant.id;
        try{
          await new Promise<void>((resolve,reject)=>{
            const xhr=new XMLHttpRequest();xhr.open('PUT',grant.url);xhr.timeout=60000;
            for(const [key,value] of Object.entries(grant.headers))xhr.setRequestHeader(key,value);
            xhr.upload.onprogress=event=>{if(event.lengthComputable)progress.value=event.loaded/event.total;};
            xhr.onload=()=>xhr.status>=200 && xhr.status<300?resolve():reject(new Error('Upload failed'));
            xhr.onerror=xhr.ontimeout=()=>reject(new Error('Upload could not be confirmed'));
            xhr.send(file);
          });
        }catch{
          // A timeout may follow successful acceptance; confirm exactly once.
          await window.api.post('/api/files/'+id+'/complete',{});await load();return;
        }
        await window.api.post('/api/files/'+id+'/complete',{});await load();
      }catch(error){if(id){try{await window.api.delete('/api/files/'+id);}catch{}}failed(error);}
      finally{controls(false);progress.hidden=true;input.value='';}
    };
    category.onchange=()=>{void load();};dialog.oncancel=event=>{if(busy)event.preventDefault();};dialog.onclose=()=>dialog.remove();
    const actions=make('div');actions.className='month-picker-actions';actions.append(close);
    dialog.append(title,category,input,progress,status,list,actions);document.body.append(dialog);dialog.showModal();await load();
  }
  const install=()=>{
    const filters=app.querySelector('.filters');if(!filters || filters.querySelector('[data-attachments]'))return;
    const button=make('button','Attachments');button.dataset.attachments='true';button.type='button';button.onclick=()=>{void openFiles();};filters.append(button);observer.disconnect();
  };
  const observer=new MutationObserver(install);observer.observe(app,{childList:true,subtree:true});install();
})();

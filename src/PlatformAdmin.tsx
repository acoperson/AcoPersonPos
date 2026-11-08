import { useCallback, useEffect, useMemo, useState } from "react";
import { Activity, Building2, CalendarDays, CheckCircle2, ChevronRight, CreditCard, LayoutDashboard, LogOut, Menu, RefreshCw, ShieldCheck, Store, Users, Wallet, XCircle } from "lucide-react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "./lib/supabase";
import { Workspace } from "./Workspace";
import "./platform-admin.css";

type Organization = { id:string; name:string; slug:string|null; owner_email:string|null; created_at:string; store_count:number; member_count:number; plan_name:string|null; subscription_status:string|null };
type PlatformUser = { id:string; email:string|null; full_name:string|null; created_at:string; last_sign_in_at:string|null };
type Subscription = { organization_id:string; organization_name:string; owner_email:string|null; plan_name:string; status:string; starts_at:string; ends_at:string|null };
type BusinessApplication = { id:string; user_id:string; owner_email:string|null; application_type:"new_business"|"upgrade"; organization_id:string|null; business_name:string; store_name:string|null; requested_plan:string; status:string; applicant_note:string|null; admin_note:string|null; created_at:string };
type Overview = {
 stats:{organizations:number;stores:number;users:number;sales:number;qr_orders:number;subscriptions:number;active_subscriptions:number;pending_applications:number};
 organizations:Organization[];
 users:PlatformUser[];
 subscriptions:Subscription[];
 applications:BusinessApplication[];
};
type Page = "overview"|"organizations"|"users"|"subscriptions"|"applications";
const number=(value:number)=>new Intl.NumberFormat("id-ID").format(Number(value||0));
const date=(value:string|null)=>value?new Date(value).toLocaleDateString("id-ID",{day:"numeric",month:"short",year:"numeric"}):"—";

export function PlatformAdmin({user,onLogout}:{user:User;onLogout:()=>void}) {
 const [overview,setOverview]=useState<Overview|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState(""),[query,setQuery]=useState("");
 const [page,setPage]=useState<Page>("overview"),[mobile,setMobile]=useState(false),[businessWorkspace,setBusinessWorkspace]=useState(false);
 const refresh=useCallback(async()=>{
  if(!supabase)return;
  setLoading(true);setError("");
  const {data,error:requestError}=await supabase.rpc("platform_admin_overview");
  if(requestError)setError(requestError.message);else setOverview(data as Overview);
  setLoading(false);
 },[]);
 const reviewApplication=async(application:BusinessApplication,approved:boolean)=>{
  if(!supabase)return;
  const note=window.prompt(approved?"Catatan persetujuan (opsional):":"Alasan penolakan (opsional):")||null;
  const {error}=await supabase.rpc("review_business_application",{p_application_id:application.id,p_approved:approved,p_admin_note:note});
  if(error){setError(error.message);return;}
  await refresh();
 };
 useEffect(()=>{void refresh()},[refresh]);
 const organizations=useMemo(()=>{
  const rows=overview?.organizations??[],term=query.trim().toLowerCase();
  return term?rows.filter(x=>[x.name,x.owner_email??"",x.slug??"",x.plan_name??""].join(" ").toLowerCase().includes(term)):rows;
 },[overview,query]);
 const users=useMemo(()=>{
  const rows=overview?.users??[],term=query.trim().toLowerCase();
  return term?rows.filter(x=>[x.email??"",x.full_name??""].join(" ").toLowerCase().includes(term)):rows;
 },[overview,query]);
 const subscriptions=useMemo(()=>{
  const rows=overview?.subscriptions??[],term=query.trim().toLowerCase();
  return term?rows.filter(x=>[x.organization_name,x.owner_email??"",x.plan_name,x.status].join(" ").toLowerCase().includes(term)):rows;
 },[overview,query]);
 if(businessWorkspace)return <Workspace user={user} onLogout={onLogout} onBackToPlatform={()=>setBusinessWorkspace(false)}/>;
 const stats=overview?.stats;
 const pageTitle:Record<Page,string>={overview:"Platform overview",organizations:"Bisnis & organisasi",users:"Pengguna platform",subscriptions:"Langganan",applications:"Pengajuan paket"};
 return <div className="app-shell platform-shell">
  <aside className={mobile?"sidebar open":"sidebar"}>
   <div className="brand-lockup"><span className="brand-mark">A</span><span><b>ACOPOS</b><small>PLATFORM CONTROL</small></span></div>
   <div className="workspace-label">PLATFORM OWNER</div><div className="workspace-card"><span className="workspace-dot"/><span><b>Platform Console</b><small>OWNER / ADMIN</small></span><ShieldCheck size={15}/></div>
   <nav>
    <NavButton active={page==="overview"} onClick={()=>{setPage("overview");setMobile(false)}} icon={LayoutDashboard}>Ringkasan platform</NavButton>
    <NavButton active={page==="organizations"} onClick={()=>{setPage("organizations");setMobile(false)}} icon={Building2}>Bisnis & organisasi</NavButton>
    <NavButton active={page==="users"} onClick={()=>{setPage("users");setMobile(false)}} icon={Users}>Pengguna platform</NavButton>
    <NavButton active={page==="subscriptions"} onClick={()=>{setPage("subscriptions");setMobile(false)}} icon={CreditCard}>Langganan</NavButton>
    <NavButton active={page==="applications"} onClick={()=>{setPage("applications");setMobile(false)}} icon={CheckCircle2}>Pengajuan paket</NavButton>
   </nav>
   <div className="sidebar-bottom"><div className="platform-account"><span className="platform-avatar">{(user.email||"A").slice(0,1).toUpperCase()}</span><span><b>{user.email}</b><small>Platform Owner</small></span></div><button className="nav-item" onClick={()=>setBusinessWorkspace(true)}><Store size={16}/>Workspace bisnis <ChevronRight size={14}/></button><button className="nav-item" onClick={onLogout}><LogOut size={16}/>Keluar</button></div>
  </aside>
  <main className="dashboard-main">
   <header className="topbar"><button className="mobile-toggle" onClick={()=>setMobile(!mobile)}><Menu size={19}/></button><div className="crumb">ACOPOS <span>/</span> {pageTitle[page]}</div><div className="top-actions"><span className="platform-live"><i/> PLATFORM SECURE</span><button className="icon-btn" onClick={()=>void refresh()} aria-label="Muat ulang"><RefreshCw size={16}/></button></div></header>
   <section className="dash-content">
    <div className="page-heading"><div><div className="eyebrow">ACOPOS / PLATFORM MANAGEMENT</div><h1>{pageTitle[page]}</h1><p>Pusat kontrol untuk memantau ekosistem ACOPOS secara keseluruhan.</p></div><span className="date-chip">{new Date().toLocaleDateString("id-ID",{weekday:"long",day:"numeric",month:"long",year:"numeric"})}</span></div>
    {error&&<div className="platform-error">{error}</div>}
    {loading?<div className="panel loading-panel"><RefreshCw className="spin" size={20}/> Memuat data platform…</div>:<>
     {page==="overview"&&<>
      <div className="metric-grid">
       <Metric label="Bisnis terdaftar" value={number(stats?.organizations??0)} icon={Building2}/>
       <Metric label="Total toko" value={number(stats?.stores??0)} icon={Store}/>
       <Metric label="Akun pengguna" value={number(stats?.users??0)} icon={Users}/>
       <Metric label="Transaksi POS" value={number(stats?.sales??0)} icon={Wallet}/>
      </div>
      <div className="platform-grid">
       <div className="panel platform-welcome"><span className="platform-kicker"><ShieldCheck size={15}/> PLATFORM OWNER ACCESS</span><h2>Seluruh bisnis.<br/><em>Satu pusat kendali.</em></h2><p>Pantau pertumbuhan organisasi, toko, pengguna, dan aktivitas transaksi dari satu tempat.</p><button className="ui-btn primary" onClick={()=>setPage("organizations")}>Lihat semua bisnis <ChevronRight size={14}/></button></div>
       <div className="panel platform-activity"><div className="panel-head"><div><h2>Aktivitas ekosistem</h2><p>Ringkasan data lintas bisnis</p></div><Activity size={18}/></div><div className="platform-stat-row"><span>Pesanan QR tercatat</span><b>{number(stats?.qr_orders??0)}</b></div><div className="platform-stat-row"><span>Organisasi terdaftar</span><b>{number(stats?.organizations??0)}</b></div><div className="platform-stat-row"><span>Cabang operasional</span><b>{number(stats?.stores??0)}</b></div><div className="platform-stat-row"><span>Langganan aktif</span><b>{number(stats?.active_subscriptions??0)}</b></div></div>
      </div>
      <div className="panel platform-recent"><div className="panel-head"><div><h2>Bisnis terbaru</h2><p>Organisasi yang terakhir terdaftar</p></div><button className="ui-btn ghost" onClick={()=>setPage("organizations")}>Lihat semua <ChevronRight size={14}/></button></div><OrganizationTable rows={(overview?.organizations??[]).slice(0,5)}/></div>
     </>}
     {page==="organizations"&&<div className="panel platform-recent"><div className="panel-head"><div><h2>Seluruh bisnis ACOPOS</h2><p>Daftar organisasi, pemilik, cabang, anggota, dan paket.</p></div><span className="platform-count">{number(organizations.length)} bisnis</span></div><SearchBox query={query} setQuery={setQuery} placeholder="Cari nama bisnis, email owner, atau paket…"/><OrganizationTable rows={organizations}/></div>}
     {page==="users"&&<div className="panel platform-recent"><div className="panel-head"><div><h2>Pengguna terdaftar</h2><p>Daftar akun yang sudah dibuat pada ACOPOS (maksimal 100 akun terbaru).</p></div><span className="platform-count">{number(users.length)} akun</span></div><SearchBox query={query} setQuery={setQuery} placeholder="Cari nama atau email pengguna…"/><UserTable rows={users}/></div>}
     {page==="subscriptions"&&<div className="panel platform-recent"><div className="panel-head"><div><h2>Langganan bisnis</h2><p>Paket dan status langganan setiap organisasi.</p></div><span className="platform-count">{number(subscriptions.length)} langganan</span></div><SearchBox query={query} setQuery={setQuery} placeholder="Cari bisnis, pemilik, paket, atau status…"/><SubscriptionTable rows={subscriptions}/></div>}
     {page==="applications"&&<div className="panel platform-recent"><div className="panel-head"><div><h2>Pengajuan paket</h2><p>Setujui pendaftaran Paket Bisnis atau upgrade dari Paket Gratis.</p></div><span className="platform-count">{number((overview?.applications||[]).filter(a=>a.status==="pending").length)} menunggu</span></div><div className="table-wrap"><table><thead><tr><th>Bisnis</th><th>Pemohon</th><th>Jenis</th><th>Paket</th><th>Catatan</th><th>Diajukan</th><th>Tindakan</th></tr></thead><tbody>{(overview?.applications||[]).filter(a=>a.status==="pending").map(a=><tr key={a.id}><td><b>{a.business_name}</b><small className="platform-slug">{a.store_name||"Upgrade bisnis"}</small></td><td>{a.owner_email||"—"}</td><td>{a.application_type==="upgrade"?"Upgrade paket":"Bisnis baru"}</td><td>{a.requested_plan}</td><td>{a.applicant_note||"—"}</td><td>{date(a.created_at)}</td><td><div className="application-actions"><button className="ui-btn primary" onClick={()=>void reviewApplication(a,true)}><CheckCircle2 size={14}/> Setujui</button><button className="ui-btn ghost" onClick={()=>void reviewApplication(a,false)}><XCircle size={14}/> Tolak</button></div></td></tr>)}</tbody></table></div>{!(overview?.applications||[]).some(a=>a.status==="pending")&&<div className="empty-state"><CheckCircle2 size={25}/><span>Tidak ada pengajuan yang menunggu persetujuan.</span></div>}</div>}
    </>}
    <div className="platform-footnote"><CalendarDays size={14}/> Data diperbarui saat halaman dimuat atau tombol refresh digunakan.</div>
   </section>
  </main>
 </div>;
}

function NavButton({active,onClick,icon:Icon,children}:{active:boolean;onClick:()=>void;icon:typeof Building2;children:string}){return <button className={active?"nav-item active":"nav-item"} onClick={onClick}><Icon size={17}/>{children}</button>}
function SearchBox({query,setQuery,placeholder}:{query:string;setQuery:(value:string)=>void;placeholder:string}){return <div className="platform-search"><input value={query} onChange={event=>setQuery(event.target.value)} placeholder={placeholder}/></div>}
function Metric({label,value,icon:Icon}:{label:string;value:string;icon:typeof Building2}){return <div className="metric-card"><div className="metric-top"><span>{label}</span><Icon size={17}/></div><strong>{value}</strong><small>Seluruh platform ACOPOS</small></div>}
function OrganizationTable({rows}:{rows:Organization[]}){
 if(!rows.length)return <div className="empty-state"><Building2 size={25}/><span>Belum ada bisnis yang terdaftar.</span></div>;
 return <div className="table-wrap"><table><thead><tr><th>Bisnis</th><th>Pemilik</th><th>Toko</th><th>Anggota</th><th>Paket</th><th>Status</th><th>Terdaftar</th></tr></thead><tbody>{rows.map(item=><tr key={item.id}><td><b>{item.name}</b><small className="platform-slug">{item.slug||item.id.slice(0,8)}</small></td><td>{item.owner_email||"—"}</td><td>{number(item.store_count)}</td><td>{number(item.member_count)}</td><td>{item.plan_name||"Starter"}</td><td><span className="status">{item.subscription_status||"Belum ada"}</span></td><td>{date(item.created_at)}</td></tr>)}</tbody></table></div>;
}
function UserTable({rows}:{rows:PlatformUser[]}){
 if(!rows.length)return <div className="empty-state"><Users size={25}/><span>Belum ada pengguna.</span></div>;
 return <div className="table-wrap"><table><thead><tr><th>Nama</th><th>Email</th><th>Dibuat</th><th>Login terakhir</th></tr></thead><tbody>{rows.map(item=><tr key={item.id}><td>{item.full_name||"—"}</td><td>{item.email||"—"}</td><td>{date(item.created_at)}</td><td>{date(item.last_sign_in_at)}</td></tr>)}</tbody></table></div>;
}
function SubscriptionTable({rows}:{rows:Subscription[]}){
 if(!rows.length)return <div className="empty-state"><CreditCard size={25}/><span>Belum ada langganan.</span></div>;
 return <div className="table-wrap"><table><thead><tr><th>Bisnis</th><th>Pemilik</th><th>Paket</th><th>Status</th><th>Mulai</th><th>Berakhir</th></tr></thead><tbody>{rows.map(item=><tr key={item.organization_id}><td><b>{item.organization_name}</b></td><td>{item.owner_email||"—"}</td><td>{item.plan_name}</td><td><span className="status">{item.status}</span></td><td>{date(item.starts_at)}</td><td>{date(item.ends_at)}</td></tr>)}</tbody></table></div>;
}

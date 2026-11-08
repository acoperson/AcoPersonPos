import { useEffect, useMemo, useState } from "react";
import { ArrowDown, ArrowRight, ArrowUpRight, CalendarClock, ChartNoAxesCombined, ChevronDown, LayoutDashboard, LogOut, Menu, Package, QrCode, Settings, ShieldCheck, ShoppingBag, Sparkles, Users } from "lucide-react";
import type { FormEvent } from "react";
import type { User } from "@supabase/supabase-js";
import { isSupabaseConfigured, supabase } from "./lib/supabase";
import { Workspace, QROrderPage } from "./Workspace";
import "./workspace.css";

type Role = "owner" | "admin" | "manager" | "cashier" | "employee";
type Profile = { full_name: string | null; active_organization_id: string | null };
const modules = [
  {id:"overview",label:"Ringkasan",icon:LayoutDashboard},
  {id:"pos",label:"Kasir / POS",icon:ShoppingBag},
  {id:"orders",label:"Pesanan QR",icon:QrCode},
  {id:"products",label:"Produk & Stok",icon:Package},
  {id:"employees",label:"Karyawan",icon:Users},
  {id:"attendance",label:"Absensi & Shift",icon:CalendarClock},
  {id:"reports",label:"Laporan",icon:ChartNoAxesCombined},
  {id:"settings",label:"Pengaturan",icon:Settings}
];
function App() {
  const [user,setUser] = useState<User|null>(null);
  const [profile,setProfile] = useState<Profile|null>(null);
  const [role,setRole] = useState<Role|null>(null);
  const [page,setPage] = useState("overview");
  const [email,setEmail] = useState("");
  const [otp,setOtp] = useState("");
  const [otpSent,setOtpSent] = useState(false);
  const [busy,setBusy] = useState(false);
  const [notice,setNotice] = useState("");
  const [authLoading,setAuthLoading] = useState(true);
  const [mobileMenu,setMobileMenu] = useState(false);
  const [showBusinessForm,setShowBusinessForm] = useState(false);
  const [businessName,setBusinessName] = useState("");
  const [storeName,setStoreName] = useState("");

  useEffect(() => {
    if (!supabase) { setAuthLoading(false); return; }
    supabase.auth.getSession().then(({data}) => setUser(data.session?.user ?? null));
    const {data:{subscription}} = supabase.auth.onAuthStateChange((_event,session) => setUser(session?.user ?? null));
    return () => subscription.unsubscribe();
  },[]);
  useEffect(() => {
    async function loadProfile() {
      if (!user || !supabase) { setProfile(null); setRole(null); setAuthLoading(false); return; }
      setAuthLoading(true);
      const {data:p} = await supabase.from("profiles").select("full_name,active_organization_id").eq("id",user.id).maybeSingle();
      setProfile(p);
      if (p?.active_organization_id) {
        const {data:m} = await supabase.from("memberships").select("role").eq("user_id",user.id).eq("organization_id",p.active_organization_id).maybeSingle();
        setRole((m?.role as Role) ?? null);
      }
      setAuthLoading(false);
    }
    loadProfile();
  },[user]);
  const title = useMemo(() => modules.find(m=>m.id===page)?.label ?? "Ringkasan",[page]);

  async function sendOtp(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true); setNotice("");
    const {error} = await supabase.auth.signInWithOtp({email:email.trim(),options:{shouldCreateUser:true}});
    setBusy(false);
    if(error) setNotice(error.message); else {setOtpSent(true);setNotice("Kode verifikasi telah dikirim ke email kamu.");}
  }
  async function verifyOtp(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true);setNotice("");
    const {error} = await supabase.auth.verifyOtp({email:email.trim(),token:otp.trim(),type:"email"});
    setBusy(false); if(error) setNotice(error.message);
  }
  async function createBusiness(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true); setNotice("");
    const {data,error} = await supabase.rpc("create_business",{p_business_name:businessName.trim(),p_store_name:storeName.trim()});
    setBusy(false);
    if(error) { setNotice(error.message); return; }
    setProfile(current=>({full_name:current?.full_name ?? user?.email?.split("@")[0] ?? "Owner",active_organization_id:data as string}));
    setRole("owner"); setShowBusinessForm(false); setNotice("Bisnis dan toko pertama berhasil dibuat.");
  }
  async function logout(){await supabase?.auth.signOut();setPage("overview");}
  if(authLoading) return <div className="boot"><div className="brand-mark">A</div><span>Menyiapkan ACOPOS…</span></div>;
  if(window.location.pathname.startsWith("/order/")) return <QROrderPage slug={window.location.pathname.split("/")[2]||""}/>;
  if(user) return <Workspace user={user} onLogout={logout}/>;
  return <div className="site">
    <header className="site-nav"><a className="brand-lockup" href="#"><span className="brand-mark">A</span><span><b>ACOPOS</b><small>BUSINESS OS</small></span></a><nav className="public-links"><a href="#ecosystem">Ekosistem</a><a href="#features">Fitur</a><a href="#pricing">Paket</a></nav><button className="nav-cta" onClick={()=>{document.getElementById("login")?.scrollIntoView({behavior:"smooth"})}}>Masuk workspace <ArrowUpRight size={14}/></button></header>
    <main>
      <section className="hero">
        <div className="hero-glow"></div><div className="hero-copy"><div className="eyebrow"><span className="eyebrow-line"></span> THE OPERATING SYSTEM FOR BUSINESS</div><h1>Bisnis bergerak.<br/><em>Kendali tetap</em> di tangan.</h1><p>Satukan kasir, inventori, pesanan pelanggan, tim, dan laporan dalam satu ekosistem yang terasa sederhana — bahkan saat bisnis berkembang.</p><div className="hero-actions"><a className="primary-btn" href="#login">Mulai kelola bisnis <ArrowUpRight size={14}/></a><a className="text-link" href="#ecosystem">Jelajahi ekosistem <ArrowDown size={14}/></a></div><div className="hero-proof"><span className="proof-icon"><ShieldCheck size={17}/></span><span>Dibuat untuk operasional yang lebih teratur.</span></div></div>
        <div className="hero-art"><div className="orbit orbit-one"></div><div className="orbit orbit-two"></div><div className="silver-core"><span>A</span><small>ACOPOS</small></div><div className="float-card float-top"><span className="mini-icon"><ArrowUpRight size={15}/></span><span><b>One connected system</b><small>Semua bergerak bersama</small></span></div><div className="float-card float-bottom"><span className="pulse-dot"></span><span><b>Business in control</b><small>Real-time workspace</small></span></div><div className="art-caption">01 / ONE BUSINESS ECOSYSTEM</div></div>
        <div className="hero-index">01 <span>—</span> 04</div>
      </section>
      <section className="ticker"><span>POINT OF SALE</span><Sparkles size={12} strokeWidth={1.6}/><span>INVENTORY</span><Sparkles size={12} strokeWidth={1.6}/><span>TEAM MANAGEMENT</span><Sparkles size={12} strokeWidth={1.6}/><span>SMART REPORTS</span><Sparkles size={12} strokeWidth={1.6}/><span>QR ORDERING</span></section>
      <section className="intro section-wrap" id="ecosystem"><div className="section-kicker">02 / THE ECOSYSTEM</div><div className="intro-grid"><h2>Satu pusat kendali.<br/><em>Seluruh bisnis.</em></h2><div><p className="large-copy">Tidak perlu berpindah-pindah aplikasi untuk memahami apa yang terjadi di bisnis kamu.</p><p className="muted-copy">ACOPOS menghubungkan aktivitas di toko dengan keputusan di level pemilik. Dari transaksi pertama sampai ringkasan performa.</p></div></div><div className="ecosystem-visual"><div className="eco-center"><span>A</span><b>ACOPOS</b><small>CONNECTED BUSINESS</small></div>{["POS & CASHIER","PRODUCTS","PEOPLE","ORDERS","INSIGHTS"].map((x,i)=><div className={"eco-node node-"+i} key={x}><i>{[ShoppingBag,Package,Users,QrCode,ChartNoAxesCombined][i] && (()=>{const Icon=[ShoppingBag,Package,Users,QrCode,ChartNoAxesCombined][i];return <Icon size={14} strokeWidth={1.7}/>})()}</i>{x}</div>)}</div></section>
      <section className="features-section" id="features"><div className="section-wrap"><div className="section-kicker">03 / BUILT TO WORK TOGETHER</div><div className="feature-heading"><h2>Operasional yang terasa<br/><em>lebih ringan.</em></h2><p>Fondasi yang kuat untuk aktivitas harian, kontrol yang jelas untuk pertumbuhan jangka panjang.</p></div><div className="feature-grid"><article className="feature-card feature-dark"><span className="feature-number">01 / TRANSACTIONS</span><div className="feature-symbol"><ShoppingBag size={27} strokeWidth={1.5}/></div><h3>Kasir tanpa kerumitan.</h3><p>Alur transaksi, shift kasir, dan riwayat penjualan berada dalam satu tempat.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card"><span className="feature-number">02 / INVENTORY</span><div className="feature-symbol"><Package size={27} strokeWidth={1.5}/></div><h3>Stok lebih terpantau.</h3><p>Kelola produk, kategori, harga, dan pergerakan persediaan secara terstruktur.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card"><span className="feature-number">03 / CUSTOMER ORDERS</span><div className="feature-symbol"><QrCode size={27} strokeWidth={1.5}/></div><h3>Pesanan dari QR.</h3><p>Pelanggan dapat melihat menu dan mengirim pesanan dari ponsel mereka.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card"><span className="feature-number">04 / PEOPLE</span><div className="feature-symbol"><Users size={27} strokeWidth={1.5}/></div><h3>Tim dalam satu ritme.</h3><p>Atur karyawan, jadwal, absensi, dan pembagian shift toko.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card feature-wide"><div><span className="feature-number">05 / BUSINESS INTELLIGENCE</span><div className="feature-symbol"><ChartNoAxesCombined size={27} strokeWidth={1.5}/></div><h3>Keputusan dengan gambaran utuh.</h3><p>Ringkasan penjualan dan aktivitas toko membantu pemilik memahami bisnis tanpa kehilangan detail operasional.</p></div><div className="mini-chart"><div className="chart-label">BUSINESS OVERVIEW <span>LIVE WORKSPACE</span></div><div className="chart-bars">{[32,48,38,68,54,82,61,92,72,100,79,88].map((h,i)=><i key={i} style={{height:h+"%"}}/>)}</div><div className="chart-foot"><span>CONNECTED DATA</span><b>ONE VIEW. MORE CLARITY.</b></div></div></article></div></div></section>
      <section className="pricing section-wrap" id="pricing"><div className="section-kicker">04 / SIMPLE BY DESIGN</div><div className="pricing-row"><div><h2>Mulai dari yang penting.<br/><em>Berkembang dengan percaya diri.</em></h2><p className="muted-copy">Paket dan kapasitas bisnis akan ditampilkan secara transparan. Hubungi tim ACOPOS untuk informasi akses awal.</p></div><div className="pricing-card"><span className="pricing-label">ACOPOS WORKSPACE</span><h3>One platform.</h3><p>POS · Inventory · People · Orders · Reports</p><a href="#login">Masuk ke workspace <ArrowUpRight size={14}/></a></div></div></section>
      <section className="login-section" id="login"><div className="login-intro"><div className="section-kicker">YOUR BUSINESS, CONNECTED</div><h2>Ruang kendali<br/><em>dimulai di sini.</em></h2><p>Masuk dengan email. Kami akan mengirimkan kode verifikasi satu kali.</p><div className="login-security"><ShieldCheck size={18}/> Secure email verification</div></div><div className="login-card"><div className="login-card-top"><span className="brand-mark">A</span><span className="secure-label"><i/> SECURE ACCESS</span></div><h3>{otpSent?"Periksa email kamu.":"Selamat datang kembali."}</h3><p>{otpSent?"Masukkan kode 6 digit yang dikirim ke alamat email kamu.":"Masukkan email untuk menerima kode verifikasi sekali pakai."}</p>
        {!isSupabaseConfigured&&<div className="notice error">Koneksi Supabase belum tersedia. Periksa Environment Variables Netlify.</div>}
        {!otpSent?<form onSubmit={sendOtp}><label>EMAIL ADDRESS</label><input type="email" required placeholder="nama@bisnis.com" value={email} onChange={e=>setEmail(e.target.value)}/><button className="primary-btn full" disabled={busy||!isSupabaseConfigured}>{busy?"Mengirim…":"Kirim kode verifikasi"} <ArrowRight size={14}/></button></form>:<form onSubmit={verifyOtp}><label>KODE VERIFIKASI</label><input className="otp-input" inputMode="numeric" autoComplete="one-time-code" maxLength={6} pattern="[0-9]{6}" required placeholder="000000" value={otp} onChange={e=>setOtp(e.target.value.replace(/\D/g,"").slice(0,6))}/><button className="primary-btn full" disabled={busy||otp.length!==6}>{busy?"Memverifikasi…":"Verifikasi & masuk"} <ArrowRight size={14}/></button><button type="button" className="resend-btn" onClick={()=>{setOtpSent(false);setOtp("");setNotice("")}}>Gunakan email lain / kirim ulang</button></form>}
        {notice&&<div className="notice">{notice}</div>}<div className="login-card-foot">Dengan masuk, kamu menyetujui ketentuan penggunaan ACOPOS.</div></div></section>
    </main><footer className="footer"><a className="brand-lockup" href="#"><span className="brand-mark">A</span><span><b>ACOPOS</b><small>BUSINESS OS</small></span></a><span>© {new Date().getFullYear()} ACOPOS. Built for better business.</span><span>BUSINESS, IN CONTROL.</span></footer>
  </div>;
}
export default App;
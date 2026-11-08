import { useEffect, useMemo, useState } from "react";
import { ArrowDown, ArrowRight, ArrowUpRight, Building2, CalendarClock, ChartNoAxesCombined, ChevronDown, LayoutDashboard, LogOut, Menu, Package, QrCode, Settings, ShieldCheck, ShoppingBag, Sparkles, Users } from "lucide-react";
import type { FormEvent } from "react";
import type { User } from "@supabase/supabase-js";
import { isSupabaseConfigured, supabase } from "./lib/supabase";
import { Workspace, QROrderPage } from "./Workspace";
import { PlatformAdmin } from "./PlatformAdmin";
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
  const [password,setPassword] = useState("");
  const [authMode,setAuthMode] = useState<"password"|"otp"|"signup"|"reset">("password");
  const [otp,setOtp] = useState("");
  const [otpSent,setOtpSent] = useState(false);
  const [busy,setBusy] = useState(false);
  const [notice,setNotice] = useState("");
  const [authLoading,setAuthLoading] = useState(true);
  const [isPlatformAdmin,setIsPlatformAdmin] = useState(false);
  const [platformAccessLoading,setPlatformAccessLoading] = useState(true);
  const [mobileMenu,setMobileMenu] = useState(false);
  const [showBusinessForm,setShowBusinessForm] = useState(false);
  const [businessName,setBusinessName] = useState("");
  const [storeName,setStoreName] = useState("");

  useEffect(() => {
    if (!supabase) { setAuthLoading(false); return; }
    supabase.auth.getSession().then(({data}) => setUser(data.session?.user ?? null));
    const {data:{subscription}} = supabase.auth.onAuthStateChange((event,session) => { if(event === "PASSWORD_RECOVERY") setAuthMode("reset"); setUser(session?.user ?? null); });
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
  useEffect(() => {
    let active = true;
    if (!user || !supabase) {
      setIsPlatformAdmin(false);
      setPlatformAccessLoading(false);
      return () => { active = false; };
    }
    setPlatformAccessLoading(true);
    supabase.rpc("is_platform_admin").then(({ data, error }) => {
      if (!active) return;
      setIsPlatformAdmin(!error && data === true);
      setPlatformAccessLoading(false);
    });
    return () => { active = false; };
  }, [user]);

  useEffect(() => {
    const nodes = Array.from(document.querySelectorAll<HTMLElement>("[data-reveal]"));
    if (!("IntersectionObserver" in window)) {
      nodes.forEach(node => node.classList.add("is-visible"));
      return;
    }
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    nodes.forEach(node => observer.observe(node));
    return () => observer.disconnect();
  }, [authLoading, user, authMode]);

  const title = useMemo(() => modules.find(m=>m.id===page)?.label ?? "Ringkasan",[page]);

  async function signInPassword(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true); setNotice("");
    const {error} = await supabase.auth.signInWithPassword({email:email.trim(),password});
    setBusy(false);
    if(error) setNotice("Email atau password tidak sesuai. Periksa kembali atau gunakan OTP.");
  }
  async function signUpPassword(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true); setNotice("");
    const {data,error} = await supabase.auth.signUp({email:email.trim(),password,options:{emailRedirectTo:window.location.origin}});
    setBusy(false);
    if(error) { setNotice(error.message); return; }
    if(data.session) setNotice("Akun berhasil dibuat. Selamat datang di ACOPOS.");
    else setNotice("Akun berhasil didaftarkan. Periksa email untuk konfirmasi sebelum masuk.");
    setAuthMode("password");
  }
  async function sendPasswordReset(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true); setNotice("");
    const {error} = await supabase.auth.resetPasswordForEmail(email.trim(),{redirectTo:window.location.origin});
    setBusy(false);
    if(error) setNotice(error.message); else setNotice("Tautan pengaturan ulang password telah dikirim jika email terdaftar.");
  }
  async function saveNewPassword(e:FormEvent) {
    e.preventDefault(); if(!supabase) return;
    setBusy(true); setNotice("");
    const {error} = await supabase.auth.updateUser({password});
    setBusy(false);
    if(error) { setNotice(error.message); return; }
    setPassword(""); setAuthMode("password"); await supabase.auth.signOut();
    setNotice("Password berhasil diperbarui. Silakan masuk dengan password baru.");
  }
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
  if(authLoading || (user && platformAccessLoading)) return <div className="boot"><div className="brand-mark">A</div><span>Menyiapkan ACOPOS…</span></div>;
  if(window.location.pathname.startsWith("/order/")) return <QROrderPage slug={window.location.pathname.split("/")[2]||""}/>;
  if(user && authMode !== "reset" && isPlatformAdmin) return <PlatformAdmin user={user} onLogout={logout}/>;
  if(user && authMode !== "reset") return <Workspace user={user} onLogout={logout}/>;
  return <div className="site">
    <header className="site-nav"><a className="brand-lockup" href="#"><span className="brand-mark">A</span><span><b>ACOPOS</b><small>BUSINESS OS</small></span></a><nav className="public-links"><a href="#ecosystem">Ekosistem</a><a href="#features">Fitur</a><a href="#foundations">Fondasi</a><a href="#pricing">Paket</a></nav><button className="nav-cta" onClick={()=>{document.getElementById("login")?.scrollIntoView({behavior:"smooth"})}}>Masuk workspace <ArrowUpRight size={14}/></button></header>
    <main>
      <section className="hero">
        <div className="hero-glow"></div><div className="hero-copy"><div className="eyebrow"><span className="eyebrow-line"></span> THE OPERATING SYSTEM FOR BUSINESS</div><h1>Bisnis bergerak.<br/><em>Kendali tetap</em> di tangan.</h1><p>Satukan kasir, inventori, pesanan pelanggan, tim, dan laporan dalam satu ekosistem yang terasa sederhana — bahkan saat bisnis berkembang.</p><div className="hero-actions"><a className="primary-btn" href="#login">Mulai kelola bisnis <ArrowUpRight size={14}/></a><a className="text-link" href="#ecosystem">Jelajahi ekosistem <ArrowDown size={14}/></a></div><div className="hero-proof"><span className="proof-icon"><ShieldCheck size={17}/></span><span>Dibuat untuk operasional yang lebih teratur.</span></div></div>
        <div className="hero-art"><div className="orbit orbit-one"></div><div className="orbit orbit-two"></div><div className="silver-core"><span>A</span><small>ACOPOS</small></div><div className="float-card float-top"><span className="mini-icon"><ArrowUpRight size={15}/></span><span><b>One connected system</b><small>Semua bergerak bersama</small></span></div><div className="float-card float-bottom"><span className="pulse-dot"></span><span><b>Business in control</b><small>Real-time workspace</small></span></div><div className="art-caption">01 / ONE BUSINESS ECOSYSTEM</div></div>
        <div className="hero-index">01 <span>—</span> 04</div>
      </section>
      <section className="ticker"><span>POINT OF SALE</span><Sparkles size={12} strokeWidth={1.6}/><span>INVENTORY</span><Sparkles size={12} strokeWidth={1.6}/><span>TEAM MANAGEMENT</span><Sparkles size={12} strokeWidth={1.6}/><span>SMART REPORTS</span><Sparkles size={12} strokeWidth={1.6}/><span>QR ORDERING</span></section>
      <section className="intro section-wrap" id="ecosystem" data-reveal><div className="section-kicker">02 / THE ECOSYSTEM</div><div className="intro-grid"><h2>Satu pusat kendali.<br/><em>Seluruh bisnis.</em></h2><div><p className="large-copy">Tidak perlu berpindah-pindah aplikasi untuk memahami apa yang terjadi di bisnis kamu.</p><p className="muted-copy">ACOPOS menghubungkan aktivitas di toko dengan keputusan di level pemilik. Dari transaksi pertama sampai ringkasan performa.</p></div></div><div className="ecosystem-visual"><div className="eco-center"><span>A</span><b>ACOPOS</b><small>CONNECTED BUSINESS</small></div>{["POS & CASHIER","PRODUCTS","PEOPLE","ORDERS","INSIGHTS"].map((x,i)=><div className={"eco-node node-"+i} key={x}><i>{[ShoppingBag,Package,Users,QrCode,ChartNoAxesCombined][i] && (()=>{const Icon=[ShoppingBag,Package,Users,QrCode,ChartNoAxesCombined][i];return <Icon size={14} strokeWidth={1.7}/>})()}</i>{x}</div>)}</div></section>
      <section className="features-section" id="features" data-reveal><div className="section-wrap"><div className="section-kicker">03 / BUILT TO WORK TOGETHER</div><div className="feature-heading"><h2>Operasional yang terasa<br/><em>lebih ringan.</em></h2><p>Fondasi yang kuat untuk aktivitas harian, kontrol yang jelas untuk pertumbuhan jangka panjang.</p></div><div className="feature-grid"><article className="feature-card feature-dark" data-reveal><span className="feature-number">01 / TRANSACTIONS</span><div className="feature-symbol"><ShoppingBag size={27} strokeWidth={1.5}/></div><h3>Kasir tanpa kerumitan.</h3><p>Alur transaksi, shift kasir, dan riwayat penjualan berada dalam satu tempat.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card" data-reveal><span className="feature-number">02 / INVENTORY</span><div className="feature-symbol"><Package size={27} strokeWidth={1.5}/></div><h3>Stok lebih terpantau.</h3><p>Kelola produk, kategori, harga, dan pergerakan persediaan secara terstruktur.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card"><span className="feature-number">03 / CUSTOMER ORDERS</span><div className="feature-symbol"><QrCode size={27} strokeWidth={1.5}/></div><h3>Pesanan dari QR.</h3><p>Pelanggan dapat melihat menu dan mengirim pesanan dari ponsel mereka.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card"><span className="feature-number">04 / PEOPLE</span><div className="feature-symbol"><Users size={27} strokeWidth={1.5}/></div><h3>Tim dalam satu ritme.</h3><p>Atur karyawan, jadwal, absensi, dan pembagian shift toko.</p><span className="feature-arrow"><ArrowUpRight size={15}/></span></article><article className="feature-card feature-wide" data-reveal><div><span className="feature-number">05 / BUSINESS INTELLIGENCE</span><div className="feature-symbol"><ChartNoAxesCombined size={27} strokeWidth={1.5}/></div><h3>Keputusan dengan gambaran utuh.</h3><p>Ringkasan penjualan dan aktivitas toko membantu pemilik memahami bisnis tanpa kehilangan detail operasional.</p></div><div className="mini-chart"><div className="chart-label">BUSINESS OVERVIEW <span>LIVE WORKSPACE</span></div><div className="chart-bars">{[32,48,38,68,54,82,61,92,72,100,79,88].map((h,i)=><i key={i} style={{height:h+"%"}}/>)}</div><div className="chart-foot"><span>CONNECTED DATA</span><b>ONE VIEW. MORE CLARITY.</b></div></div></article></div></div></section>
      <section className="foundations-section section-wrap" id="foundations" data-reveal><div className="section-kicker">04 / FOUR CORE FOUNDATIONS</div><div className="foundations-heading"><h2>Empat fondasi.<br/><em>Satu ekosistem bisnis.</em></h2><p>Setiap bagian ACOPOS dirancang untuk saling terhubung — dari kendali pemilik hingga aktivitas harian di toko.</p></div><div className="foundations-grid"><article><span>01 / BUSINESS MANAGEMENT</span><Building2/><h3>Business Management</h3><p>Kelola bisnis, cabang, hak akses, paket, dan kontrol Owner dalam satu pusat kendali.</p></article><article><span>02 / STORE OPERATIONS</span><ShoppingBag/><h3>Store Operations</h3><p>POS, produk, stok, pesanan QR, dan pembayaran manual yang terhubung dengan operasional toko.</p></article><article><span>03 / WORKFORCE MANAGEMENT</span><Users/><h3>Workforce Management</h3><p>Atur karyawan, peran, jadwal, absensi, dan shift kasir secara terstruktur.</p></article><article><span>04 / BUSINESS INTELLIGENCE</span><ChartNoAxesCombined/><h3>Business Intelligence</h3><p>Pantau penjualan, transaksi, persediaan, dan aktivitas bisnis melalui laporan terpadu.</p></article></div></section>
      <section className="pricing section-wrap" id="pricing" data-reveal><div className="section-kicker">05 / SIMPLE BY DESIGN</div><div className="pricing-row"><div><h2>Mulai dari yang penting.<br/><em>Berkembang dengan percaya diri.</em></h2><p className="muted-copy">Pilih paket yang sesuai. Pendaftaran Gratis langsung aktif, sedangkan Paket Bisnis dan upgrade akan ditinjau Platform Owner.</p></div><div className="pricing-cards"><article className="pricing-card"><span className="pricing-label">MULAI TANPA BIAYA</span><h3>Gratis</h3><strong className="pricing-amount">Rp0</strong><p>Daftar bisnis dan langsung gunakan workspace setelah akun dibuat.</p><a href="#login">Daftar Paket Gratis <ArrowUpRight size={14}/></a></article><article className="pricing-card pricing-card-business"><span className="pricing-label">UNTUK BISNIS BERKEMBANG</span><h3>Bisnis</h3><strong className="pricing-amount">Paket berbayar</strong><p>Pengajuan bisnis baru dan upgrade dari Gratis memerlukan persetujuan admin. Detail harga ditampilkan setelah ditetapkan.</p><a href="#login">Ajukan Paket Bisnis <ArrowUpRight size={14}/></a></article></div></div></section>
      <section className="login-section" id="login" data-reveal><div className="login-intro"><div className="section-kicker">YOUR BUSINESS, CONNECTED</div><h2>Ruang kendali<br/><em>dimulai di sini.</em></h2><p>Masuk dengan email dan password, atau gunakan kode OTP 6 digit.</p><div className="login-security"><ShieldCheck size={18}/> Secure account access</div></div><div className="login-card"><div className="login-card-top"><span className="brand-mark">A</span><span className="secure-label"><i/> SECURE ACCESS</span></div>
        <h3>{authMode==="otp"?(otpSent?"Periksa email kamu.":"Masuk dengan kode OTP"):authMode==="signup"?"Buat akun ACOPOS":authMode==="reset"?"Atur password baru":authMode==="password"?"Selamat datang kembali.":"Akses akun ACOPOS"}</h3>
        <p>{authMode==="otp"?(otpSent?"Masukkan kode 6 digit yang dikirim ke email kamu.":"Kami akan mengirim kode verifikasi ke email kamu."):authMode==="signup"?"Daftarkan email dan buat password minimal 8 karakter.":authMode==="reset"?"Buat password baru untuk akun kamu.":"Masuk menggunakan email dan password akun ACOPOS."}</p>
        {!isSupabaseConfigured&&<div className="notice error">Koneksi Supabase belum tersedia. Periksa Environment Variables Netlify.</div>}
        {authMode==="password"&&<form onSubmit={signInPassword}><label>EMAIL ADDRESS</label><input type="email" required autoComplete="email" placeholder="nama@bisnis.com" value={email} onChange={e=>setEmail(e.target.value)}/><label>PASSWORD</label><input type="password" required autoComplete="current-password" placeholder="Masukkan password" value={password} onChange={e=>setPassword(e.target.value)}/><button className="primary-btn full" disabled={busy||!isSupabaseConfigured}>{busy?"Memproses…":"Masuk"} <ArrowRight size={14}/></button><button type="button" className="resend-btn" onClick={()=>{setAuthMode("reset");setNotice("");}}>Lupa password?</button><button type="button" className="resend-btn" onClick={()=>{setAuthMode("signup");setNotice("");}}>Belum punya akun? Daftar</button></form>}
        {authMode==="signup"&&<form onSubmit={signUpPassword}><label>EMAIL ADDRESS</label><input type="email" required autoComplete="email" placeholder="nama@bisnis.com" value={email} onChange={e=>setEmail(e.target.value)}/><label>PASSWORD BARU</label><input type="password" required minLength={8} autoComplete="new-password" placeholder="Minimal 8 karakter" value={password} onChange={e=>setPassword(e.target.value)}/><button className="primary-btn full" disabled={busy||!isSupabaseConfigured}>{busy?"Mendaftarkan…":"Buat akun"} <ArrowRight size={14}/></button><button type="button" className="resend-btn" onClick={()=>{setAuthMode("password");setNotice("");}}>Kembali ke login</button></form>}
        {authMode==="reset"&&<form onSubmit={user?saveNewPassword:sendPasswordReset}><label>{user?"PASSWORD BARU":"EMAIL ADDRESS"}</label><input type={user?"password":"email"} required minLength={user?8:undefined} autoComplete={user?"new-password":"email"} placeholder={user?"Minimal 8 karakter":"nama@bisnis.com"} value={user?password:email} onChange={e=>user?setPassword(e.target.value):setEmail(e.target.value)}/><button className="primary-btn full" disabled={busy||!isSupabaseConfigured}>{busy?"Memproses…":user?"Simpan password baru":"Kirim tautan reset"} <ArrowRight size={14}/></button><button type="button" className="resend-btn" onClick={()=>{setAuthMode("password");setPassword("");setNotice("");}}>Kembali ke login</button></form>}
        {authMode==="otp"&&(!otpSent?<form onSubmit={sendOtp}><label>EMAIL ADDRESS</label><input type="email" required autoComplete="email" placeholder="nama@bisnis.com" value={email} onChange={e=>setEmail(e.target.value)}/><button className="primary-btn full" disabled={busy||!isSupabaseConfigured}>{busy?"Mengirim…":"Kirim kode OTP"} <ArrowRight size={14}/></button></form>:<form onSubmit={verifyOtp}><label>KODE VERIFIKASI</label><input className="otp-input" inputMode="numeric" autoComplete="one-time-code" maxLength={6} pattern="[0-9]{6}" required placeholder="000000" value={otp} onChange={e=>setOtp(e.target.value.replace(/\D/g,"").slice(0,6))}/><button className="primary-btn full" disabled={busy||otp.length!==6}>{busy?"Memverifikasi…":"Verifikasi & masuk"} <ArrowRight size={14}/></button><button type="button" className="resend-btn" onClick={()=>{setOtpSent(false);setOtp("");setNotice("");}}>Gunakan email lain / kirim ulang</button></form>)}
        {authMode!=="otp"&&authMode!=="reset"&&<div className="auth-divider"><span>ATAU</span></div>}
        {authMode!=="otp"&&authMode!=="reset"&&<button type="button" className="otp-alt-btn" onClick={()=>{setAuthMode("otp");setOtpSent(false);setOtp("");setNotice("");}}>Masuk dengan kode OTP 6 digit</button>}
        {authMode==="otp"&&<button type="button" className="resend-btn" onClick={()=>{setAuthMode("password");setOtpSent(false);setOtp("");setNotice("");}}>Kembali ke login password</button>}
        {notice&&<div className="notice">{notice}</div>}<div className="login-card-foot">Dengan masuk, kamu menyetujui ketentuan penggunaan ACOPOS.</div></div></section>
    </main><footer className="footer"><a className="brand-lockup" href="#"><span className="brand-mark">A</span><span><b>ACOPOS</b><small>BUSINESS OS</small></span></a><span>© {new Date().getFullYear()} ACOPOS. Built for better business.</span><span>BUSINESS, IN CONTROL.</span></footer>
  </div>;
}
export default App;
import { useCallback, useEffect, useMemo, useState } from "react";
import { Activity, Building2, CalendarDays, ChevronRight, LayoutDashboard, LogOut, Menu, RefreshCw, ShieldCheck, Store, Users, Wallet } from "lucide-react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "./lib/supabase";
import { Workspace } from "./Workspace";
import "./platform-admin.css";

type Organization = {
  id: string;
  name: string;
  slug: string | null;
  owner_email: string | null;
  created_at: string;
  store_count: number;
  member_count: number;
  plan_name: string | null;
  subscription_status: string | null;
};
type Overview = {
  stats: { organizations: number; stores: number; users: number; sales: number; qr_orders: number };
  organizations: Organization[];
};

const number = (value: number) => new Intl.NumberFormat("id-ID").format(Number(value || 0));
const date = (value: string) => new Date(value).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" });

export function PlatformAdmin({ user, onLogout }: { user: User; onLogout: () => void }) {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState<"overview" | "organizations">("overview");
  const [mobile, setMobile] = useState(false);
  const [businessWorkspace, setBusinessWorkspace] = useState(false);

  const refresh = useCallback(async () => {
    if (!supabase) return;
    setLoading(true);
    setError("");
    const { data, error: requestError } = await supabase.rpc("platform_admin_overview");
    if (requestError) setError(requestError.message);
    else setOverview(data as Overview);
    setLoading(false);
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const organizations = useMemo(() => {
    const rows = overview?.organizations ?? [];
    const term = query.trim().toLowerCase();
    if (!term) return rows;
    return rows.filter((item) => [item.name, item.owner_email ?? "", item.slug ?? "", item.plan_name ?? ""].join(" ").toLowerCase().includes(term));
  }, [overview, query]);

  if (businessWorkspace) return <Workspace user={user} onLogout={onLogout} onBackToPlatform={() => setBusinessWorkspace(false)} />;

  const stats = overview?.stats;
  return (
    <div className="app-shell platform-shell">
      <aside className={mobile ? "sidebar open" : "sidebar"}>
        <div className="brand-lockup"><span className="brand-mark">A</span><span><b>ACOPOS</b><small>PLATFORM CONTROL</small></span></div>
        <div className="workspace-label">PLATFORM OWNER</div>
        <div className="workspace-card"><span className="workspace-dot"/><span><b>Platform Console</b><small>OWNER / ADMIN</small></span><ShieldCheck size={15}/></div>
        <nav>
          <button className={page === "overview" ? "nav-item active" : "nav-item"} onClick={() => { setPage("overview"); setMobile(false); }}><LayoutDashboard size={17}/>Ringkasan platform</button>
          <button className={page === "organizations" ? "nav-item active" : "nav-item"} onClick={() => { setPage("organizations"); setMobile(false); }}><Building2 size={17}/>Bisnis & organisasi</button>
        </nav>
        <div className="sidebar-bottom">
          <div className="platform-account"><span className="platform-avatar">{(user.email || "A").slice(0,1).toUpperCase()}</span><span><b>{user.email}</b><small>Platform Owner</small></span></div>
          <button className="nav-item" onClick={() => setBusinessWorkspace(true)}><Store size={16}/>Workspace bisnis <ChevronRight size={14}/></button>
          <button className="nav-item" onClick={onLogout}><LogOut size={16}/>Keluar</button>
        </div>
      </aside>
      <main className="dashboard-main">
        <header className="topbar">
          <button className="mobile-toggle" onClick={() => setMobile(!mobile)}><Menu size={19}/></button>
          <div className="crumb">ACOPOS <span>/</span> {page === "overview" ? "Ringkasan platform" : "Bisnis & organisasi"}</div>
          <div className="top-actions"><span className="platform-live"><i/> PLATFORM SECURE</span><button className="icon-btn" onClick={() => void refresh()} aria-label="Muat ulang"><RefreshCw size={16}/></button></div>
        </header>
        <section className="dash-content">
          <div className="page-heading"><div><div className="eyebrow">ACOPOS / PLATFORM MANAGEMENT</div><h1>{page === "overview" ? "Platform overview" : "Bisnis & organisasi"}</h1><p>Pusat kontrol untuk memantau ekosistem ACOPOS secara keseluruhan.</p></div><span className="date-chip">{new Date().toLocaleDateString("id-ID", { weekday: "long", day: "numeric", month: "long", year: "numeric" })}</span></div>
          {error && <div className="platform-error">{error}</div>}
          {loading ? <div className="panel loading-panel"><RefreshCw className="spin" size={20}/> Memuat data platform…</div> : <>
            {page === "overview" && <>
              <div className="metric-grid">
                <Metric label="Bisnis terdaftar" value={number(stats?.organizations ?? 0)} icon={Building2}/>
                <Metric label="Total toko" value={number(stats?.stores ?? 0)} icon={Store}/>
                <Metric label="Akun pengguna" value={number(stats?.users ?? 0)} icon={Users}/>
                <Metric label="Transaksi POS" value={number(stats?.sales ?? 0)} icon={Wallet}/>
              </div>
              <div className="platform-grid">
                <div className="panel platform-welcome"><span className="platform-kicker"><ShieldCheck size={15}/> PLATFORM OWNER ACCESS</span><h2>Seluruh bisnis.<br/><em>Satu pusat kendali.</em></h2><p>Pantau pertumbuhan organisasi, toko, pengguna, dan aktivitas transaksi dari satu tempat.</p><button className="ui-btn primary" onClick={() => setPage("organizations")}>Lihat semua bisnis <ChevronRight size={14}/></button></div>
                <div className="panel platform-activity"><div className="panel-head"><div><h2>Aktivitas ekosistem</h2><p>Ringkasan data lintas bisnis</p></div><Activity size={18}/></div><div className="platform-stat-row"><span>Pesanan QR tercatat</span><b>{number(stats?.qr_orders ?? 0)}</b></div><div className="platform-stat-row"><span>Organisasi terdaftar</span><b>{number(stats?.organizations ?? 0)}</b></div><div className="platform-stat-row"><span>Cabang operasional</span><b>{number(stats?.stores ?? 0)}</b></div><div className="platform-stat-row"><span>Pengguna terdaftar</span><b>{number(stats?.users ?? 0)}</b></div></div>
              </div>
              <div className="panel platform-recent"><div className="panel-head"><div><h2>Bisnis terbaru</h2><p>Organisasi yang terakhir terdaftar</p></div><button className="ui-btn ghost" onClick={() => setPage("organizations")}>Lihat semua <ChevronRight size={14}/></button></div><OrganizationTable rows={(overview?.organizations ?? []).slice(0,5)}/></div>
            </>}
            {page === "organizations" && <div className="panel platform-recent"><div className="panel-head"><div><h2>Seluruh bisnis ACOPOS</h2><p>Daftar organisasi, pemilik, cabang, anggota, dan paket.</p></div><span className="platform-count">{number(organizations.length)} bisnis</span></div><div className="platform-search"><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Cari nama bisnis, email owner, atau paket…"/></div><OrganizationTable rows={organizations}/></div>}
          </>}
          <div className="platform-footnote"><CalendarDays size={14}/> Data diperbarui saat halaman dimuat atau tombol refresh digunakan.</div>
        </section>
      </main>
    </div>
  );
}

function Metric({ label, value, icon: Icon }: { label: string; value: string; icon: typeof Building2 }) {
  return <div className="metric-card"><div className="metric-top"><span>{label}</span><Icon size={17}/></div><strong>{value}</strong><small>Seluruh platform ACOPOS</small></div>;
}

function OrganizationTable({ rows }: { rows: Organization[] }) {
  if (!rows.length) return <div className="empty-state"><Building2 size={25}/><span>Belum ada bisnis yang terdaftar.</span></div>;
  return <div className="table-wrap"><table><thead><tr><th>Bisnis</th><th>Pemilik</th><th>Toko</th><th>Anggota</th><th>Paket</th><th>Status</th><th>Terdaftar</th></tr></thead><tbody>{rows.map((item) => <tr key={item.id}><td><b>{item.name}</b><small className="platform-slug">{item.slug || item.id.slice(0,8)}</small></td><td>{item.owner_email || "—"}</td><td>{number(item.store_count)}</td><td>{number(item.member_count)}</td><td>{item.plan_name || "Starter"}</td><td><span className="status">{item.subscription_status || "Belum ada"}</span></td><td>{date(item.created_at)}</td></tr>)}</tbody></table></div>;
}

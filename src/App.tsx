import { useEffect, useMemo, useState } from "react"

type Screen = "home" | "inventory" | "requests" | "returns" | "profile"
type LoginRole = "student" | "admin"
type SupportSection = "chat" | "help" | "preferences"
type AdminTab = "dashboard" | "stock" | "qr" | "requests" | "missing" | "database" | "reports" | "accounts" | "analytics" | "settings"
type IconName = "home" | "box" | "clipboard" | "rotate" | "user" | "bell" | "search" | "scan" | "arrow" | "clock" | "check" | "chevron" | "filter" | "close" | "calendar" | "shield" | "settings" | "help" | "logout" | "wallet" | "camera" | "alert" | "history" | "key" | "info" | "student" | "admin"

type IconProps = {
  name: IconName
  size?: number
}

type HeaderProps = {
  title: string
  sub?: string
}

type HomeProps = {
  go: (screen: Screen) => void
  scan: () => void
  penaltyAmount: number
}

type NavItem = {
  id: Screen
  label: string
  icon: IconName
}

type ProfileProps = {
  pay: () => void
  logout: () => void
  penaltyAmount: number
  photo: string
  editPhoto: () => void
  openSupport: (section: SupportSection) => void
}

type LoginProps = {
  onLogin: (
    role: LoginRole,
    accountId: string,
    password: string,
  ) => string | null
  onRegister: (
    role: LoginRole,
    accountId: string,
    name: string,
    password: string,
  ) => string | null
  onResetPassword: (
    role: LoginRole,
    accountId: string,
    password: string,
  ) => string | null
}

type AdminDashboardProps = {
  accountId: string
  logout: () => void
  photo: string
  editPhoto: () => void
  openSupport: (section: SupportSection) => void
}

type AdminRequest = {
  id: string
  student: string
  item: string
}

type AdminTabItem = {
  id: AdminTab
  label: string
  icon: IconName
}

type AdminModuleProps = {
  tab: AdminTab
  requests: AdminRequest[]
  reviewRequest: (id: string, action: "approved" | "rejected") => void
  openSupport: (section: SupportSection) => void
  equipmentItems: typeof equipment
  missingIds: string[]
  markMissing: (id: string) => void
  removeEquipment: (id: string) => void
}

type PhotoEditorProps = {
  currentPhoto: string
  onSave: (photo: string) => void
  close: () => void
}

type SupportHubProps = {
  initialSection: SupportSection
  close: () => void
  darkMode: boolean
  toggleDarkMode: () => void
}

const paths: Record<IconName, string[]> = {
  home: ["M3 11.5 12 4l9 7.5", "M5 10v10h14V10", "M9 20v-6h6v6"],
  box: ["m21 8-9 5-9-5", "m3.3 7 8.7-5 8.7 5v10L12 22 3.3 17Z", "M12 13v9"],
  clipboard: [
    "M9 5H6a2 2 0 0 0-2 2v13h16V7a2 2 0 0 0-2-2h-3",
    "M9 3h6v4H9Z",
    "M8 12h8",
    "M8 16h5",
  ],
  rotate: [
    "M20 7v5h-5",
    "M4 17v-5h5",
    "M6.1 9a7 7 0 0 1 11.5-2L20 12",
    "M4 12l2.4 4.8A7 7 0 0 0 18 15",
  ],
  user: ["M20 21a8 8 0 0 0-16 0", "M12 13a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z"],
  bell: ["M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9", "M10 21h4"],
  search: ["m21 21-4.4-4.4", "M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z"],
  scan: ["M3 9V4h5", "M16 4h5v5", "M21 15v5h-5", "M8 20H3v-5", "M7 12h10"],
  arrow: ["M5 12h14", "m13 6 6 6-6 6"],
  clock: ["M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z", "M12 6v6l4 2"],
  check: ["m5 12 4 4L19 6"],
  chevron: ["m9 18 6-6-6-6"],
  filter: ["M4 5h16", "M7 12h10", "M10 19h4"],
  close: ["M6 6l12 12", "M18 6 6 18"],
  calendar: [
    "M6 2v4",
    "M18 2v4",
    "M3 9h18",
    "M5 4h14a2 2 0 0 1 2 2v15H3V6a2 2 0 0 1 2-2Z",
  ],
  shield: ["M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z", "m9 12 2 2 4-4"],
  settings: [
    "M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z",
    "M19.4 15a2 2 0 0 0 .4 2.2l.1.1-2.6 2.6-.1-.1a2 2 0 0 0-2.2-.4 2 2 0 0 0-1.2 1.8V21h-3.6v-.2A2 2 0 0 0 9 19a2 2 0 0 0-2.2.4l-.1.1-2.6-2.6.1-.1A2 2 0 0 0 4.6 15a2 2 0 0 0-1.8-1.2H3v-3.6h.2A2 2 0 0 0 5 9a2 2 0 0 0-.4-2.2l-.1-.1 2.6-2.6.1.1A2 2 0 0 0 9 4.6a2 2 0 0 0 1.2-1.8V3h3.6v.2A2 2 0 0 0 15 5a2 2 0 0 0 2.2-.4l.1-.1 2.6 2.6-.1.1A2 2 0 0 0 19.4 9a2 2 0 0 0 1.8 1.2h.2v3.6h-.2a2 2 0 0 0-1.8 1.2Z",
  ],
  help: [
    "M9.5 9a2.6 2.6 0 1 1 4 2.2c-1 .7-1.5 1.2-1.5 2.3",
    "M12 18h.01",
    "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z",
  ],
  logout: [
    "M10 17l5-5-5-5",
    "M15 12H3",
    "M15 4h5a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-5",
  ],
  wallet: ["M3 6h16a2 2 0 0 1 2 2v11H3Z", "M3 6V4h14v2", "M16 13h5"],
  camera: ["M4 7h3l2-3h6l2 3h3v13H4Z", "M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z"],
  alert: [
    "M12 9v4",
    "M12 17h.01",
    "m10.3 3.7-9 16A2 2 0 0 0 3 22h18a2 2 0 0 0 1.7-3.3l-9-16a2 2 0 0 0-3.4 0Z",
  ],
  history: ["M3 12a9 9 0 1 0 3-6.7L3 8", "M3 3v5h5", "M12 7v5l3 2"],
  key: [
    "M21 2 13.6 9.4",
    "M15.5 4.5l4 4",
    "M10 13a5 5 0 1 1-7.1 7.1A5 5 0 0 1 10 13Z",
  ],
  info: ["M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Z", "M12 11v6", "M12 7h.01"],
  student: [
    "m2 9 10-5 10 5-10 5Z",
    "M6 11.5V16c2.8 2.5 9.2 2.5 12 0v-4.5",
    "M22 9v6",
  ],
  admin: [
    "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z",
    "M9.5 11a2.5 2.5 0 1 0 5 0 2.5 2.5 0 0 0-5 0Z",
    "M8 18a4 4 0 0 1 8 0",
  ],
}

function Icon({ name, size = 20 }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name].map((d, i) => (
        <path d={d} key={i} />
      ))}
    </svg>
  )
}

const images = {
  displayPort: "/assets/stokli/display-port.jpg",
  keyboard: "/assets/stokli/rgb-keyboard.jpg",
  mouse: "/assets/stokli/rgb-mouse.jpg",
  speakerBluetooth: "/assets/stokli/rgb-speaker-bluetooth.jpg",
  speakerDesktop: "/assets/stokli/rgb-speaker-desktop.jpg",
  screwdriver: "/assets/stokli/screw-driver-set.jpg",
  thermalPaste: "/assets/stokli/thermal-paste.jpg",
  vgaPort: "/assets/stokli/vga-port.jpg",
}

const equipment = [
  {
    id: "STK-001",
    name: "Display Port",
    brand: "Stokli",
    category: "Cables",
    program: "IT Laboratory",
    stock: 5,
    condition: "Good",
    image: images.displayPort,
  },
  {
    id: "STK-002",
    name: "RGB Keyboard",
    brand: "Stokli",
    category: "Peripherals",
    program: "IT Laboratory",
    stock: 3,
    condition: "Good",
    image: images.keyboard,
  },
  {
    id: "STK-003",
    name: "RGB Mouse",
    brand: "Stokli",
    category: "Peripherals",
    program: "IT Laboratory",
    stock: 5,
    condition: "Good",
    image: images.mouse,
  },
  {
    id: "STK-004",
    name: "RGB Speaker Bluetooth",
    brand: "Stokli",
    category: "Audio",
    program: "IT Laboratory",
    stock: 2,
    condition: "Good",
    image: images.speakerBluetooth,
  },
  {
    id: "STK-005",
    name: "RGB Speaker Desktop",
    brand: "Stokli",
    category: "Audio",
    program: "IT Laboratory",
    stock: 4,
    condition: "Good",
    image: images.speakerDesktop,
  },
  {
    id: "STK-006",
    name: "Screw Driver Set",
    brand: "Stokli",
    category: "Tools",
    program: "IT Laboratory",
    stock: 3,
    condition: "Good",
    image: images.screwdriver,
  },
  {
    id: "STK-007",
    name: "Thermal Paste",
    brand: "Stokli",
    category: "Tools",
    program: "IT Laboratory",
    stock: 5,
    condition: "Good",
    image: images.thermalPaste,
  },
  {
    id: "STK-008",
    name: "VGA Port",
    brand: "Stokli",
    category: "Cables",
    program: "IT Laboratory",
    stock: 4,
    condition: "Good",
    image: images.vgaPort,
  },
]

type Account = {
  id: string
  password: string
  name: string
}

type AccountStore = Record<LoginRole, Account[]>

const seedAccounts: AccountStore = {
  student: [
    {
      id: "STUDENT-001",
      password: "demo-student",
      name: "Demo Student 1",
    },
    { id: "STUDENT-002", password: "demo-student", name: "Demo Student 2" },
    {
      id: "STUDENT-003",
      password: "demo-student",
      name: "Demo Student 3",
    },
    { id: "STUDENT-004", password: "demo-student", name: "Demo Student 4" },
    { id: "STUDENT-005", password: "demo-student", name: "Demo Student 5" },
    { id: "STUDENT-006", password: "demo-student", name: "Demo Student 6" },
  ],
  admin: [
    { id: "ADMIN-001", password: "demo-admin", name: "Demo Admin 1" },
    { id: "ADMIN-002", password: "demo-admin", name: "Demo Admin 2" },
  ],
}

const ACCOUNT_STORAGE_KEY = "stokli_accounts_v3"

function loadAccountStore(): AccountStore {
  const fallback: AccountStore = {
    student: seedAccounts.student.map((account) => ({ ...account })),
    admin: seedAccounts.admin.map((account) => ({ ...account })),
  }
  try {
    const saved = JSON.parse(
      window.localStorage.getItem(ACCOUNT_STORAGE_KEY) ?? "{}",
    ) as Partial<AccountStore>
    for (const role of ["student", "admin"] as LoginRole[]) {
      for (const account of saved[role] ?? []) {
        if (!account?.id || !account?.password || !account?.name) continue
        const index = fallback[role].findIndex(
          (candidate) =>
            candidate.id.toLowerCase() === account.id.toLowerCase(),
        )
        if (index >= 0) fallback[role][index] = account
        else fallback[role].push(account)
      }
    }
  } catch {
    window.localStorage.removeItem(ACCOUNT_STORAGE_KEY)
  }
  return fallback
}

const nav: NavItem[] = [
  { id: "home", label: "Home", icon: "home" },
  { id: "inventory", label: "Inventory", icon: "box" },
  { id: "requests", label: "Requests", icon: "clipboard" },
  { id: "returns", label: "Returns", icon: "rotate" },
  { id: "profile", label: "Profile", icon: "user" },
]

function Logo() {
  return (
    <div className="logo">
      <img src="/assets/stokli/stokli-logo.jpg" alt="Stokli logo" />
      <div>
        <b>STOKLI</b>
        <small>Inventory return & tracking</small>
      </div>
    </div>
  )
}

function StatusPill({
  children,
  tone = "blue",
}: {
  children: React.ReactNode
  tone?: "blue" | "green" | "amber" | "red" | "gray"
}) {
  return <span className={`status ${tone}`}>{children}</span>
}

function Header({ title, sub }: HeaderProps) {
  return (
    <header className="topbar">
      <div className="header-title">
        <img src="/assets/stokli/stokli-logo.jpg" alt="" />
        <div>
          <p className="eyebrow">{sub || "Student portal"}</p>
          <h1>{title}</h1>
        </div>
      </div>
      <button className="icon-btn notification" aria-label="Notifications">
        <Icon name="bell" />
        <i />
      </button>
    </header>
  )
}

function Home({ go, scan, penaltyAmount }: HomeProps) {
  return (
    <div className="page">
      <Header title="Good morning, Mark" sub="Tuesday, 26 September" />
      <section className="hero-card">
        <div className="hero-head">
          <div>
            <span className="hero-kicker">ACTIVE BORROWING</span>
            <h2>Stokli RGB Keyboard</h2>
            <p>
              <Icon name="clock" size={15} /> 5h 42m remaining
            </p>
          </div>
          <div className="hero-icon">
            <Icon name="box" size={26} />
          </div>
        </div>
        <div className="progress">
          <i />
        </div>
        <div className="hero-foot">
          <span>Due today, 4:30 PM</span>
          <button onClick={() => go("returns")}>
            View details <Icon name="arrow" size={15} />
          </button>
        </div>
      </section>

      <section className="quick-grid">
        <button className="quick-card primary" onClick={scan}>
          <span>
            <Icon name="scan" size={24} />
          </span>
          <b>Scan to borrow</b>
          <small>Use equipment QR code</small>
        </button>
        <button className="quick-card" onClick={() => go("inventory")}>
          <span>
            <Icon name="search" size={24} />
          </span>
          <b>Browse inventory</b>
          <small>8 Stokli items</small>
        </button>
      </section>

      <section className="section">
        <div className="section-title">
          <div>
            <p className="eyebrow">OVERVIEW</p>
            <h2>Your activity</h2>
          </div>
          <button onClick={() => go("requests")}>View all</button>
        </div>
        <div className="metrics">
          <div>
            <span className="metric-icon blue">
              <Icon name="box" />
            </span>
            <p>Currently borrowed</p>
            <b>1</b>
          </div>
          <div>
            <span className="metric-icon amber">
              <Icon name="clock" />
            </span>
            <p>Pending requests</p>
            <b>2</b>
          </div>
          <div>
            <span className="metric-icon green">
              <Icon name="check" />
            </span>
            <p>Returned on time</p>
            <b>14</b>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="section-title">
          <div>
            <p className="eyebrow">LATEST</p>
            <h2>Recent requests</h2>
          </div>
        </div>
        <div className="list-card">
          <div className="request-row">
            <div className="request-icon">
              <Icon name="clipboard" />
            </div>
            <div>
              <b>Stokli RGB Mouse</b>
              <p>Requested today, 8:12 AM</p>
            </div>
            <StatusPill tone="amber">Pending</StatusPill>
          </div>
          <div className="request-row">
            <div className="request-icon">
              <Icon name="clipboard" />
            </div>
            <div>
              <b>Stokli Display Port</b>
              <p>Approved yesterday</p>
            </div>
            <StatusPill tone="green">Approved</StatusPill>
          </div>
        </div>
      </section>
      <div className={`safety-note ${penaltyAmount > 0 ? "warning" : ""}`}>
        <Icon name={penaltyAmount > 0 ? "alert" : "shield"} />
        <div>
          <b>
            {penaltyAmount > 0
              ? `₱${penaltyAmount.toFixed(2)} payment required`
              : "Your account is in good standing"}
          </b>
          <p>
            {penaltyAmount > 0
              ? "Settle the outstanding penalty from your profile to restore full clearance."
              : "No overdue items or unpaid penalties."}
          </p>
        </div>
      </div>
    </div>
  )
}

function Inventory({
  select,
}: {
  select: (item: typeof equipment[0]) => void
}) {
  const [query, setQuery] = useState("")
  const [cat, setCat] = useState("All")
  const filtered = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase()
    return equipment.filter((item) => {
      const matchesCategory = cat === "All" || item.category === cat
      const searchableText = [
        item.name,
        item.brand,
        item.id,
        item.category,
        item.program,
      ]
        .join(" ")
        .toLowerCase()
      return matchesCategory && searchableText.includes(normalizedQuery)
    })
  }, [query, cat])
  return (
    <div className="page">
      <Header title="Equipment inventory" sub="Browse & request" />
      <div className="search-wrap">
        <Icon name="search" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search equipment, brand..."
        />
        <button aria-label="Filter">
          <Icon name="filter" />
        </button>
      </div>
      <div className="chips">
        {["All", "Cables", "Peripherals", "Audio", "Tools"].map((c) => (
          <button
            key={c}
            className={cat === c ? "active" : ""}
            onClick={() => setCat(c)}
          >
            {c}
          </button>
        ))}
      </div>
      <div className="inventory-head">
        <p>
          <b>{filtered.length}</b> items available
        </p>
        <span>Updated just now</span>
      </div>
      <div className="equipment-grid">
        {filtered.map((item) => (
          <button
            className="equipment-card"
            key={item.id}
            onClick={() => select(item)}
          >
            <div className="equipment-img">
              <img src={item.image} alt={item.name} />
              <StatusPill tone="green">Available</StatusPill>
            </div>
            <div className="equipment-body">
              <p>
                {item.brand} • {item.id}
              </p>
              <h3>{item.name}</h3>
              <div>
                <span>{item.condition}</span>
                <b>{item.stock} in stock</b>
              </div>
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}

function Requests({ newlyRequested }: { newlyRequested: string[] }) {
  const [tab, setTab] = useState("Pending")
  const newRequests = newlyRequested.map((name) => ({
    name,
    meta: "Requested just now",
    tone: "amber" as const,
  }))
  const data =
    tab === "Pending"
      ? [
          ...newRequests,
          {
            name: "Stokli RGB Mouse",
            meta: "Requested today, 8:12 AM",
            tone: "amber" as const,
          },
          {
            name: "Stokli Thermal Paste",
            meta: "Requested Sep 25, 3:40 PM",
            tone: "amber" as const,
          },
        ]
      : tab === "Approved"
        ? [
            {
              name: "Stokli Display Port",
              meta: "Approved Sep 25 • Ready for pickup",
              tone: "green" as const,
            },
          ]
        : [
            {
              name: "Stokli RGB Speaker Desktop",
              meta: "Unavailable during selected period",
              tone: "red" as const,
            },
          ]
  return (
    <div className="page">
      <Header title="My requests" sub="Borrowing activity" />
      <div className="segmented">
        {["Pending", "Approved", "Rejected"].map((t) => (
          <button
            className={t === tab ? "active" : ""}
            key={t}
            onClick={() => setTab(t)}
          >
            {t}
            <span>{t === "Pending" ? 2 + newlyRequested.length : 1}</span>
          </button>
        ))}
      </div>
      <div className="request-stack">
        {data.map((r, i) => (
          <div className="request-detail" key={`${r.name}-${i}`}>
            <div className="request-top">
              <div className="request-icon">
                <Icon name="box" />
              </div>
              <div>
                <p>REQ-2026-00{48 + i}</p>
                <h3>{r.name}</h3>
              </div>
              <StatusPill tone={r.tone}>{tab}</StatusPill>
            </div>
            <div className="timeline">
              <div className="timeline-step done">
                <i>
                  <Icon name="check" size={13} />
                </i>
                <div>
                  <b>Request submitted</b>
                  <small>{r.meta}</small>
                </div>
              </div>
              <div
                className={`timeline-step ${tab !== "Pending" ? "done" : ""}`}
              >
                <i>{tab !== "Pending" && <Icon name="check" size={13} />}</i>
                <div>
                  <b>
                    {tab === "Rejected"
                      ? "Request reviewed"
                      : tab === "Approved"
                        ? "Request approved"
                        : "Awaiting review"}
                  </b>
                  <small>
                    {tab === "Rejected"
                      ? "Unavailable during selected period"
                      : tab === "Approved"
                        ? "Approved Sep 25 • Ready for pickup"
                        : "Usually within 2 school hours"}
                  </small>
                </div>
              </div>
            </div>
            <button className="text-action">
              View request details <Icon name="chevron" size={17} />
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}

function Returns({ report }: { report: () => void }) {
  const [photoName, setPhotoName] = useState("")
  return (
    <div className="page">
      <Header title="Return item" sub="Active borrowing" />
      <div className="return-card">
        <div className="return-cover">
          <img src={images.keyboard} alt="Stokli RGB Keyboard" />
          <span>
            <Icon name="clock" size={16} /> Due in 5h 42m
          </span>
        </div>
        <div className="return-content">
          <p>STOKLI • STK-002</p>
          <h2>Stokli RGB Keyboard</h2>
          <div className="detail-grid">
            <div>
              <small>Borrowed</small>
              <b>Today, 8:30 AM</b>
            </div>
            <div>
              <small>Due time</small>
              <b>Today, 4:30 PM</b>
            </div>
            <div>
              <small>Condition before</small>
              <b>Good</b>
            </div>
            <div>
              <small>Borrow method</small>
              <b>Mobile QR scan</b>
            </div>
          </div>
          <div className="qr-faux" aria-label="Equipment QR code">
            <div>▦</div>
            <span>STK-002-0091</span>
          </div>
        </div>
      </div>
      <div className="return-steps">
        <p className="eyebrow">RETURN PROCESS</p>
        <h2>Complete your return</h2>
        <input
          className="visually-hidden"
          id="return-photo"
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(event) =>
            setPhotoName(event.target.files?.[0]?.name ?? "")
          }
        />
        <button
          onClick={() => document.getElementById("return-photo")?.click()}
        >
          <span>
            <Icon name={photoName ? "check" : "camera"} />
          </span>
          <div>
            <b>{photoName ? "Photo ready" : "Upload condition photo"}</b>
            <small>{photoName || "Required to confirm the item's state"}</small>
          </div>
          <Icon name="chevron" />
        </button>
        <button
          className={!photoName ? "disabled-step" : ""}
          disabled={!photoName}
          onClick={report}
        >
          <span>
            <Icon name="check" />
          </span>
          <div>
            <b>Confirm item condition</b>
            <small>
              {photoName
                ? "Choose good, damaged, or missing"
                : "Upload a return photo first"}
            </small>
          </div>
          <Icon name="chevron" />
        </button>
      </div>
      <div className="info-note">
        <Icon name="info" />
        <p>
          Returns are finalized after a staff member verifies the item and its
          condition.
        </p>
      </div>
    </div>
  )
}

function Profile({
  pay,
  logout,
  penaltyAmount,
  photo,
  editPhoto,
  openSupport,
}: ProfileProps) {
  return (
    <div className="page">
      <Header title="My account" sub="Student profile" />
      <div className="profile-card">
        <button className="avatar profile-avatar" onClick={editPhoto}>
          {photo ? <img src={photo} alt="Demo Student 1" /> : "DS"}
          <span>
            <Icon name="camera" size={13} />
          </span>
        </button>
        <div>
          <h2>Demo Student 1</h2>
          <p>STUDENT-001</p>
          <StatusPill tone="green">Active student</StatusPill>
        </div>
      </div>
      <div className="profile-info">
        <div>
          <small>Program & section</small>
          <b>BSIT 204</b>
        </div>
        <div>
          <small>Contact number</small>
          <b>0912 345 6789</b>
        </div>
      </div>
      <div className="menu-section">
        <p className="eyebrow">ACCOUNT</p>
        <button>
          <span>
            <Icon name="history" />
          </span>
          <div>
            <b>Borrowing history</b>
            <small>Last 30 days</small>
          </div>
          <Icon name="chevron" />
        </button>
        <button onClick={pay}>
          <span>
            <Icon name="wallet" />
          </span>
          <div>
            <b>Penalties & payments</b>
            <small>
              {penaltyAmount > 0
                ? `₱${penaltyAmount.toFixed(2)} outstanding`
                : "No unsettled balance"}
            </small>
          </div>
          <Icon name="chevron" />
        </button>
        <button>
          <span>
            <Icon name="key" />
          </span>
          <div>
            <b>Security & password</b>
            <small>Last changed 2 months ago</small>
          </div>
          <Icon name="chevron" />
        </button>
      </div>
      <div className="menu-section">
        <p className="eyebrow">SUPPORT</p>
        <button onClick={() => openSupport("preferences")}>
          <span>
            <Icon name="settings" />
          </span>
          <div>
            <b>App preferences</b>
            <small>Notifications and accessibility</small>
          </div>
          <Icon name="chevron" />
        </button>
        <button onClick={() => openSupport("help")}>
          <span>
            <Icon name="help" />
          </span>
          <div>
            <b>Help center</b>
            <small>Borrowing rules and support</small>
          </div>
          <Icon name="chevron" />
        </button>
        <button onClick={() => openSupport("chat")}>
          <span>
            <Icon name="help" />
          </span>
          <div>
            <b>AI chat support</b>
            <small>Ask how the Stokli system works</small>
          </div>
          <Icon name="chevron" />
        </button>
      </div>
      <button className="logout-btn" onClick={logout}>
        <Icon name="logout" /> Log out
      </button>
      <p className="version">
        STOKLI EQUIPMENT BORROWING AND RETRUN TRACKING SYSTEM
        <br />
        Version 1.0.0
      </p>
    </div>
  )
}

function AdminModule({
  tab,
  requests,
  reviewRequest,
  openSupport,
  equipmentItems,
  missingIds,
  markMissing,
  removeEquipment,
}: AdminModuleProps) {
  const downloadReport = (name: string) => {
    const content = [
      "STOKLI EQUIPMENT BORROWING AND RETRUN TRACKING SYSTEM",
      name,
      `Generated: ${new Date().toLocaleString()}`,
      "",
      "Equipment,Status,Stock",
      ...equipmentItems.map(
        (item) =>
          `${item.name},${
            missingIds.includes(item.id) ? "Missing" : "Available"
          },${item.stock}`,
      ),
    ].join("\n")
    const url = URL.createObjectURL(new Blob([content], { type: "text/csv" }))
    const anchor = document.createElement("a")
    anchor.href = url
    anchor.download = `${name.toLowerCase().replace(/ /g, "-")}.csv`
    anchor.click()
    URL.revokeObjectURL(url)
  }

  if (tab === "stock") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">8 OFFICIAL ITEMS</p>
            <h2>Current equipment inventory</h2>
          </div>
          <StatusPill tone="green">
            {equipmentItems
              .filter((item) => !missingIds.includes(item.id))
              .reduce((total, item) => total + item.stock, 0)}{" "}
            available
          </StatusPill>
        </div>
        <div className="admin-record-table equipment-records">
          {equipmentItems.map((item) => (
            <article key={item.id}>
              <img src={item.image} alt={item.name} />
              <div>
                <b>{item.name}</b>
                <small>
                  {item.id} • Stokli • {item.category}
                </small>
              </div>
              <span>{item.stock} total</span>
              <StatusPill tone={missingIds.includes(item.id) ? "red" : "green"}>
                {missingIds.includes(item.id) ? "Missing" : "Available"}
              </StatusPill>
              <div className="stock-actions">
                <button
                  className="missing"
                  disabled={missingIds.includes(item.id)}
                  onClick={() => markMissing(item.id)}
                >
                  <Icon name="alert" size={14} /> Mark missing
                </button>
                <button
                  className="remove"
                  onClick={() => removeEquipment(item.id)}
                >
                  <Icon name="close" size={14} /> Remove
                </button>
              </div>
            </article>
          ))}
          {!equipmentItems.length && (
            <div className="admin-empty">
              <Icon name="box" />
              <b>No equipment records remain</b>
            </div>
          )}
        </div>
      </section>
    )
  }

  if (tab === "qr") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">IDENTIFIERS</p>
            <h2>QR and barcode registry</h2>
          </div>
          <button
            className="module-action"
            onClick={() => downloadReport("QR Registry")}
          >
            Export registry
          </button>
        </div>
        <div className="qr-registry">
          {equipmentItems.map((item) => (
            <article key={item.id}>
              <div className="qr-mini">▦</div>
              <div>
                <b>{item.name}</b>
                <small>
                  {item.id} • STK-{item.id.slice(-3)}-2026
                </small>
              </div>
              <StatusPill tone="blue">Assigned</StatusPill>
            </article>
          ))}
        </div>
      </section>
    )
  }

  if (tab === "requests") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">APPROVAL QUEUE</p>
            <h2>{requests.length} requests awaiting review</h2>
          </div>
        </div>
        <div className="admin-request-list">
          {requests.map((request) => (
            <article key={request.id}>
              <div className="request-icon">
                <Icon name="clipboard" />
              </div>
              <div>
                <small>{request.id}</small>
                <b>{request.item}</b>
                <p>{request.student}</p>
              </div>
              <div className="admin-actions">
                <button
                  className="approve"
                  onClick={() => reviewRequest(request.id, "approved")}
                >
                  <Icon name="check" size={15} /> Approve
                </button>
                <button
                  className="reject"
                  onClick={() => reviewRequest(request.id, "rejected")}
                >
                  <Icon name="close" size={15} /> Reject
                </button>
              </div>
            </article>
          ))}
          {!requests.length && (
            <div className="admin-empty">
              <Icon name="check" />
              <b>All requests reviewed</b>
            </div>
          )}
        </div>
      </section>
    )
  }

  if (tab === "missing") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">EXCEPTION RECORDS</p>
            <h2>Missing and damaged equipment</h2>
          </div>
          <StatusPill tone="amber">2 open cases</StatusPill>
        </div>
        <div className="case-grid">
          <article>
            <span className="metric-icon amber">
              <Icon name="alert" />
            </span>
            <div>
              <b>STK-004 • RGB Speaker Bluetooth</b>
              <small>Damaged • Under staff review • Sep 25</small>
            </div>
            <StatusPill tone="amber">Review</StatusPill>
          </article>
          <article>
            <span className="metric-icon blue">
              <Icon name="search" />
            </span>
            <div>
              <b>STK-008 • VGA Port</b>
              <small>Missing • Last borrower: Demo Student 3</small>
            </div>
            <StatusPill tone="red">Missing</StatusPill>
          </article>
        </div>
      </section>
    )
  }

  if (tab === "database") {
    const records = [
      ["Users", "10", "Students, staff, and administrators"],
      ["Equipment", "8", "Official Stokli inventory"],
      ["Transactions", "48", "Borrowing and return lifecycle"],
      ["Transaction logs", "126", "Auditable system actions"],
      ["Penalty records", "4", "Overdue and missing-item records"],
      ["Payments", "3", "GCash, Maya, and cash settlements"],
    ]
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">SYSTEM RECORDS</p>
            <h2>Database overview</h2>
          </div>
          <StatusPill tone="green">Healthy</StatusPill>
        </div>
        <div className="database-list">
          {records.map(([name, count, detail]) => (
            <article key={name}>
              <span>
                <Icon name="history" />
              </span>
              <div>
                <b>{name}</b>
                <small>{detail}</small>
              </div>
              <strong>{count}</strong>
            </article>
          ))}
        </div>
      </section>
    )
  }

  if (tab === "reports") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">OFFICIAL RECORDS</p>
            <h2>Generate and download reports</h2>
          </div>
        </div>
        <div className="report-grid">
          {[
            "Borrowing History",
            "Equipment Returns",
            "Missing Equipment",
            "Penalty Records",
            "Payment Records",
            "System Analytics",
          ].map((name) => (
            <button key={name} onClick={() => downloadReport(name)}>
              <span>
                <Icon name="clipboard" />
              </span>
              <div>
                <b>{name}</b>
                <small>Current synchronized records</small>
              </div>
              <Icon name="arrow" />
            </button>
          ))}
        </div>
      </section>
    )
  }

  if (tab === "accounts") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">ROLE MANAGEMENT</p>
            <h2>System accounts</h2>
          </div>
          <button className="module-action">Add account</button>
        </div>
        <div className="account-list">
          {[...seedAccounts.admin, ...seedAccounts.student.slice(0, 4)].map(
            (account) => (
              <article key={account.id}>
                <span>
                  {account.name
                    .split(" ")
                    .map((part) => part[0])
                    .slice(0, 2)
                    .join("")}
                </span>
                <div>
                  <b>{account.name}</b>
                  <small>{account.id}</small>
                </div>
                <StatusPill
                  tone={account.id.startsWith("ADM") ? "blue" : "green"}
                >
                  {account.id.startsWith("ADM") ? "Admin" : "Student"}
                </StatusPill>
                <button>
                  <Icon name="settings" size={16} />
                </button>
              </article>
            ),
          )}
        </div>
      </section>
    )
  }

  if (tab === "analytics") {
    return (
      <section className="admin-panel admin-module">
        <div className="admin-panel-title">
          <div>
            <p className="eyebrow">LAST 30 DAYS</p>
            <h2>Utilization and activity analytics</h2>
          </div>
        </div>
        <div className="analytics-grid">
          {[
            ["Equipment utilization", 72],
            ["On-time returns", 91],
            ["Request approval rate", 84],
            ["Account activity", 68],
          ].map(([label, value]) => (
            <article key={String(label)}>
              <div>
                <b>{label}</b>
                <strong>{value}%</strong>
              </div>
              <span>
                <i className={`bar-${value}`} />
              </span>
            </article>
          ))}
        </div>
        <div className="audit-report">
          <div className="admin-panel-title">
            <div>
              <p className="eyebrow">OVERALL SYSTEM AUDIT</p>
              <h2>Traceable activity report</h2>
            </div>
            <button
              className="module-action"
              onClick={() => downloadReport("Overall System Audit")}
            >
              Download audit
            </button>
          </div>
          <div className="audit-summary">
            <div>
              <small>Total system actions</small>
              <b>126</b>
            </div>
            <div>
              <small>Authenticated users</small>
              <b>10</b>
            </div>
            <div>
              <small>Borrow transactions</small>
              <b>48</b>
            </div>
            <div>
              <small>Open exceptions</small>
              <b>2</b>
            </div>
          </div>
          <div className="audit-log">
            {[
              [
                "11:42 AM",
                "ADMIN-001",
                "Equipment status updated",
                "STK-004 marked for condition review",
              ],
              [
                "10:18 AM",
                "STUDENT-001",
                "Return submitted",
                "STK-002 return photo recorded",
              ],
              [
                "9:51 AM",
                "ADMIN-002",
                "Request approved",
                "REQ-2026-0048 approved",
              ],
              [
                "8:30 AM",
                "STUDENT-001",
                "QR borrowing completed",
                "STK-002 borrowed via mobile scan",
              ],
              [
                "8:12 AM",
                "STUDENT-001",
                "Request submitted",
                "RGB Mouse borrowing request",
              ],
            ].map(([time, user, action, description]) => (
              <article key={`${time}-${action}`}>
                <span>{time}</span>
                <div>
                  <b>{action}</b>
                  <small>{description}</small>
                </div>
                <strong>{user}</strong>
              </article>
            ))}
          </div>
        </div>
      </section>
    )
  }

  return (
    <section className="admin-panel admin-module">
      <div className="admin-panel-title">
        <div>
          <p className="eyebrow">SYSTEM CONTROL</p>
          <h2>Settings and support</h2>
        </div>
      </div>
      <div className="report-grid">
        <button onClick={() => openSupport("preferences")}>
          <span>
            <Icon name="settings" />
          </span>
          <div>
            <b>App preferences</b>
            <small>Phone permissions, notifications, and accessibility</small>
          </div>
          <Icon name="chevron" />
        </button>
        <button onClick={() => openSupport("help")}>
          <span>
            <Icon name="help" />
          </span>
          <div>
            <b>Help center</b>
            <small>Administrator workflows and system guidance</small>
          </div>
          <Icon name="chevron" />
        </button>
        <button onClick={() => openSupport("chat")}>
          <span>
            <Icon name="help" />
          </span>
          <div>
            <b>AI chat support</b>
            <small>System-specific assistance</small>
          </div>
          <Icon name="chevron" />
        </button>
      </div>
    </section>
  )
}

function AdminDashboard({
  accountId,
  logout,
  photo,
  editPhoto,
  openSupport,
}: AdminDashboardProps) {
  const [tab, setTab] = useState<AdminTab>("dashboard")
  const [requests, setRequests] = useState<AdminRequest[]>([
    { id: "REQ-2026-0051", student: "Demo Student 1", item: "RGB Mouse" },
    { id: "REQ-2026-0052", student: "Demo Student 4", item: "Thermal Paste" },
    { id: "REQ-2026-0053", student: "Demo Student 5", item: "VGA Port" },
  ])
  const [equipmentItems, setEquipmentItems] = useState([...equipment])
  const [missingIds, setMissingIds] = useState<string[]>([])
  const [notice, setNotice] = useState("")
  const adminTabs: AdminTabItem[] = [
    { id: "dashboard", label: "Dashboard", icon: "home" },
    { id: "stock", label: "Stock Checker", icon: "box" },
    { id: "qr", label: "QR Codes", icon: "scan" },
    { id: "requests", label: "Requests", icon: "clipboard" },
    { id: "missing", label: "Missing Items", icon: "alert" },
    { id: "database", label: "Database", icon: "history" },
    { id: "reports", label: "Reports", icon: "clipboard" },
    { id: "accounts", label: "Accounts", icon: "user" },
    { id: "analytics", label: "Analytics", icon: "history" },
    { id: "settings", label: "Settings", icon: "settings" },
  ]
  const tabTitles: Record<AdminTab, string> = {
    dashboard: "System overview",
    stock: "Equipment stock checker",
    qr: "QR and barcode records",
    requests: "Borrowing requests",
    missing: "Missing and damaged items",
    database: "System database records",
    reports: "Reports and exports",
    accounts: "Account management",
    analytics: "System analytics",
    settings: "Admin settings",
  }

  const reviewRequest = (id: string, action: "approved" | "rejected") => {
    setRequests((current) => current.filter((request) => request.id !== id))
    setNotice(`Request ${id} was ${action}.`)
  }

  const markMissing = (id: string) => {
    setMissingIds((current) =>
      current.includes(id) ? current : [...current, id],
    )
    setNotice(`${id} was marked missing and added to the exception audit.`)
  }

  const removeEquipment = (id: string) => {
    setEquipmentItems((current) => current.filter((item) => item.id !== id))
    setMissingIds((current) => current.filter((missingId) => missingId !== id))
    setNotice(`${id} was removed from the active inventory.`)
  }

  return (
    <div className="admin-app">
      <header className="admin-header">
        <div className="admin-brand">
          <img src="/assets/stokli/stokli-logo.jpg" alt="Stokli" />
          <div>
            <b>STOKLI ADMIN</b>
            <small>Equipment control center</small>
          </div>
        </div>
        <div className="admin-header-actions">
          <button
            onClick={() => openSupport("chat")}
            aria-label="AI chat support"
          >
            <Icon name="help" size={18} />
          </button>
          <button
            className="admin-avatar"
            onClick={editPhoto}
            aria-label="Change profile photo"
          >
            {photo ? (
              <img src={photo} alt="Admin profile" />
            ) : (
              <Icon name="admin" />
            )}
          </button>
          <button onClick={logout}>
            <Icon name="logout" size={18} /> Sign out
          </button>
        </div>
      </header>

      <nav className="admin-tabs" aria-label="Admin modules">
        {adminTabs.map((item) => (
          <button
            key={item.id}
            className={tab === item.id ? "active" : ""}
            onClick={() => setTab(item.id)}
          >
            <Icon name={item.icon} size={18} />
            <span>{item.label}</span>
            {item.id === "requests" && requests.length > 0 && (
              <i>{requests.length}</i>
            )}
          </button>
        ))}
      </nav>

      <main className="admin-page">
        <div className="admin-title">
          <div>
            <p className="eyebrow">ADMINISTRATOR WORKSPACE</p>
            <h1>{tabTitles[tab]}</h1>
            <p>
              Manage synchronized records, permissions, equipment, and system
              activity.
            </p>
          </div>
          <span>
            <Icon name="admin" />
            {accountId}
          </span>
        </div>

        {tab === "dashboard" ? (
          <>
            {notice && (
              <div className="admin-notice" role="status">
                <Icon name="check" size={17} />
                {notice}
              </div>
            )}

            <section className="admin-metrics">
              <div>
                <span className="metric-icon blue">
                  <Icon name="box" />
                </span>
                <small>Total equipment</small>
                <b>{equipmentItems.length}</b>
              </div>
              <div>
                <span className="metric-icon amber">
                  <Icon name="clipboard" />
                </span>
                <small>Pending requests</small>
                <b>{requests.length}</b>
              </div>
              <div>
                <span className="metric-icon green">
                  <Icon name="check" />
                </span>
                <small>Available stock</small>
                <b>
                  {equipmentItems
                    .filter((item) => !missingIds.includes(item.id))
                    .reduce((total, item) => total + item.stock, 0)}
                </b>
              </div>
              <div>
                <span className="metric-icon blue">
                  <Icon name="history" />
                </span>
                <small>Active borrowing</small>
                <b>1</b>
              </div>
            </section>

            <div className="admin-grid">
              <section className="admin-panel">
                <div className="admin-panel-title">
                  <div>
                    <p className="eyebrow">REVIEW QUEUE</p>
                    <h2>Borrowing requests</h2>
                  </div>
                  <StatusPill tone={requests.length ? "amber" : "green"}>
                    {requests.length
                      ? `${requests.length} pending`
                      : "All clear"}
                  </StatusPill>
                </div>
                <div className="admin-request-list">
                  {requests.length === 0 ? (
                    <div className="admin-empty">
                      <Icon name="check" />
                      <b>No pending requests</b>
                      <small>All borrowing requests have been reviewed.</small>
                    </div>
                  ) : (
                    requests.map((request) => (
                      <article key={request.id}>
                        <div className="request-icon">
                          <Icon name="clipboard" />
                        </div>
                        <div>
                          <small>{request.id}</small>
                          <b>{request.item}</b>
                          <p>{request.student}</p>
                        </div>
                        <div className="admin-actions">
                          <button
                            className="approve"
                            onClick={() =>
                              reviewRequest(request.id, "approved")
                            }
                          >
                            <Icon name="check" size={15} /> Approve
                          </button>
                          <button
                            className="reject"
                            onClick={() =>
                              reviewRequest(request.id, "rejected")
                            }
                          >
                            <Icon name="close" size={15} /> Reject
                          </button>
                        </div>
                      </article>
                    ))
                  )}
                </div>
              </section>

              <section className="admin-panel">
                <div className="admin-panel-title">
                  <div>
                    <p className="eyebrow">LIVE INVENTORY</p>
                    <h2>Equipment stock</h2>
                  </div>
                  <StatusPill tone="green">Synchronized</StatusPill>
                </div>
                <div className="admin-equipment-list">
                  {equipment.slice(0, 5).map((item) => (
                    <article key={item.id}>
                      <img src={item.image} alt={item.name} />
                      <div>
                        <b>{item.name}</b>
                        <small>{item.id} • Good condition</small>
                      </div>
                      <strong>{item.stock} available</strong>
                    </article>
                  ))}
                </div>
              </section>
            </div>
          </>
        ) : (
          <AdminModule
            tab={tab}
            requests={requests}
            reviewRequest={reviewRequest}
            openSupport={openSupport}
            equipmentItems={equipmentItems}
            missingIds={missingIds}
            markMissing={markMissing}
            removeEquipment={removeEquipment}
          />
        )}
      </main>
    </div>
  )
}

function Login({ onLogin, onRegister, onResetPassword }: LoginProps) {
  const [role, setRole] = useState<LoginRole>("student")
  const [mode, setMode] = useState<"login" | "register" | "forgot">("login")
  const [accountId, setAccountId] = useState("")
  const [name, setName] = useState("")
  const [password, setPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [remember, setRemember] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")

  const submit = (event: React.FormEvent) => {
    event.preventDefault()
    setError("")
    setSuccess("")
    if (!accountId.trim()) {
      setError("Enter your account ID.")
      return
    }

    if (mode === "login") {
      if (!password) {
        setError("Enter your password.")
        return
      }
      const loginError = onLogin(role, accountId.trim(), password)
      setError(loginError ?? "")
      return
    }

    if (mode === "register" && !name.trim()) {
      setError("Enter the account holder's full name.")
      return
    }
    if (
      password.length < 8 ||
      !/[A-Z]/.test(password) ||
      !/[a-z]/.test(password) ||
      !/\d/.test(password) ||
      !/[^A-Za-z0-9]/.test(password)
    ) {
      setError(
        "Use at least 8 characters with uppercase, lowercase, a number, and a special character.",
      )
      return
    }
    if (password !== confirmPassword) {
      setError("Passwords do not match.")
      return
    }

    const actionError =
      mode === "register"
        ? onRegister(role, accountId.trim(), name.trim(), password)
        : onResetPassword(role, accountId.trim(), password)
    if (actionError) {
      setError(actionError)
      return
    }

    setSuccess(
      mode === "register"
        ? "Account created successfully. You can now sign in."
        : "Password updated successfully. Sign in with your new password.",
    )
    setPassword("")
    setConfirmPassword("")
    setMode("login")
  }

  const switchMode = (nextMode: "login" | "register" | "forgot") => {
    setMode(nextMode)
    setAccountId("")
    setName("")
    setPassword("")
    setConfirmPassword("")
    setError("")
    setSuccess("")
  }

  const switchRole = (nextRole: LoginRole) => {
    setRole(nextRole)
    setAccountId("")
    setError("")
  }

  return (
    <main className="login-page">
      <section className="login-brand-panel">
        <div className="login-brand">
          <img src="/assets/stokli/stokli-logo.jpg" alt="Stokli" />
          <span>
            <b>STOKLI</b>
            <small>Inventory return & tracking</small>
          </span>
        </div>
        <div className="login-message">
          <h1>Stokli Equipment Borrowing and Retrun Tracking System</h1>
          <p>
            One secure place to request, borrow, return, and monitor school
            equipment.
          </p>
        </div>
        <div className="login-feature">
          <span>
            <Icon name="shield" />
          </span>
          <div>
            <b>Protected access</b>
            <small>
              Role-based access for students, staff, and administrators
            </small>
          </div>
        </div>
      </section>

      <section className={`login-form-panel auth-${mode}`}>
        <div className="login-mobile-brand">
          <img src="/assets/stokli/stokli-logo.jpg" alt="Stokli" />
          <b>STOKLI</b>
        </div>
        <div className="login-mobile-copy">
          <h1>Stokli Equipment Borrowing and Retrun Tracking System</h1>
        </div>
        <form className="login-form" onSubmit={submit} noValidate>
          <div className="login-heading">
            <p className="eyebrow">EQUIPMENT PORTAL</p>
            <h2>
              {mode === "login"
                ? "Sign in to your account"
                : mode === "register"
                  ? "Register account"
                  : "Reset your password"}
            </h2>
            <p>
              {mode === "login"
                ? "Choose your account type to continue."
                : mode === "register"
                  ? "Create a secure Student or Admin account."
                  : "Verify your account ID and create a new password."}
            </p>
          </div>

          <fieldset className="login-role-selector">
            <legend>{mode === "login" ? "Login as" : "Account type"}</legend>
            <div>
              <button
                type="button"
                className={role === "student" ? "active" : ""}
                aria-pressed={role === "student"}
                onClick={() => switchRole("student")}
              >
                <Icon name="student" size={19} />
                Student
              </button>
              <button
                type="button"
                className={role === "admin" ? "active" : ""}
                aria-pressed={role === "admin"}
                onClick={() => switchRole("admin")}
              >
                <Icon name="admin" size={19} />
                Admin
              </button>
            </div>
          </fieldset>

          {mode === "register" && (
            <label className="field">
              <span>Full name</span>
              <div>
                <Icon name="user" size={18} />
                <input
                  autoComplete="name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder="Enter the account holder's name"
                />
              </div>
            </label>
          )}

          <label className="field">
            <span>{role === "student" ? "Student ID" : "Admin ID"}</span>
            <div>
              <Icon name={role === "student" ? "student" : "admin"} size={18} />
              <input
                autoComplete="username"
                value={accountId}
                onChange={(event) => setAccountId(event.target.value)}
                placeholder={
                  role === "student"
                    ? "Enter your student ID"
                    : "Enter your admin ID"
                }
              />
            </div>
          </label>

          <label className="field">
            <span>{mode === "login" ? "Password" : "New password"}</span>
            <div>
              <Icon name="key" size={18} />
              <input
                autoComplete={
                  mode === "login" ? "current-password" : "new-password"
                }
                type={showPassword ? "text" : "password"}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                placeholder={
                  mode === "login"
                    ? "Enter your password"
                    : "Create a secure password"
                }
              />
              <button
                type="button"
                onClick={() => setShowPassword((current) => !current)}
              >
                {showPassword ? "Hide" : "Show"}
              </button>
            </div>
          </label>

          {mode !== "login" && (
            <label className="field">
              <span>Confirm password</span>
              <div>
                <Icon name="shield" size={18} />
                <input
                  autoComplete="new-password"
                  type={showPassword ? "text" : "password"}
                  value={confirmPassword}
                  onChange={(event) => setConfirmPassword(event.target.value)}
                  placeholder="Re-enter your new password"
                />
              </div>
            </label>
          )}

          {mode === "login" && (
            <div className="login-options">
              <label>
                <input
                  type="checkbox"
                  checked={remember}
                  onChange={(event) => setRemember(event.target.checked)}
                />
                <span>Remember me</span>
              </label>
              <button type="button" onClick={() => switchMode("forgot")}>
                Forgot password?
              </button>
            </div>
          )}

          {error && (
            <div className="login-error" role="alert">
              <Icon name="alert" size={17} />
              {error}
            </div>
          )}
          {success && (
            <div className="login-success" role="status">
              <Icon name="check" size={17} />
              {success}
            </div>
          )}

          <button className="login-submit" type="submit">
            {mode === "login"
              ? "Sign In"
              : mode === "register"
                ? "Create Account"
                : "Update Password"}
            <Icon name="arrow" size={18} />
          </button>

          <p className="register-prompt">
            {mode === "login" ? (
              <>
                Need an account?{" "}
                <button type="button" onClick={() => switchMode("register")}>
                  Register account
                </button>
              </>
            ) : (
              <button type="button" onClick={() => switchMode("login")}>
                Return to Sign In
              </button>
            )}
          </p>
        </form>
      </section>
    </main>
  )
}

function ProfilePhotoEditor({ currentPhoto, onSave, close }: PhotoEditorProps) {
  const [source, setSource] = useState(currentPhoto)
  const [error, setError] = useState("")

  const choosePhoto = (file?: File) => {
    if (!file) return
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      setError("Choose a JPEG, PNG, or WebP image.")
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      setError("Profile photos must be smaller than 5 MB.")
      return
    }
    const reader = new FileReader()
    reader.onload = () => {
      setSource(String(reader.result))
      setError("")
    }
    reader.readAsDataURL(file)
  }

  const cropAndSave = () => {
    if (!source) {
      setError("Choose a photo first.")
      return
    }
    const image = new Image()
    image.onload = () => {
      const size = Math.min(image.naturalWidth, image.naturalHeight)
      const canvas = document.createElement("canvas")
      canvas.width = 512
      canvas.height = 512
      const context = canvas.getContext("2d")
      if (!context) return
      context.drawImage(
        image,
        (image.naturalWidth - size) / 2,
        (image.naturalHeight - size) / 2,
        size,
        size,
        0,
        0,
        512,
        512,
      )
      onSave(canvas.toDataURL("image/jpeg", 0.9))
      close()
    }
    image.src = source
  }

  return (
    <Sheet close={close}>
      <div className="photo-editor">
        <p className="eyebrow">PROFILE PHOTO</p>
        <h2>Upload and crop photo</h2>
        <p className="sheet-sub">
          Your photo is automatically center-cropped to a clear square profile
          image.
        </p>
        <div className="crop-preview">
          {source ? (
            <img src={source} alt="Profile crop preview" />
          ) : (
            <Icon name="user" size={54} />
          )}
        </div>
        <label className="photo-upload">
          <Icon name="camera" />
          <span>Choose from phone</span>
          <input
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={(event) => choosePhoto(event.target.files?.[0])}
          />
        </label>
        {error && (
          <div className="login-error">
            <Icon name="alert" size={16} />
            {error}
          </div>
        )}
        <div className="photo-actions">
          <button
            onClick={() => {
              onSave("")
              close()
            }}
          >
            Remove photo
          </button>
          <button className="primary-btn" onClick={cropAndSave}>
            Save cropped photo
          </button>
        </div>
      </div>
    </Sheet>
  )
}

function SupportHub({
  initialSection,
  close,
  darkMode,
  toggleDarkMode,
}: SupportHubProps) {
  const [section, setSection] = useState(initialSection)
  const [message, setMessage] = useState("")
  const [messages, setMessages] = useState([
    {
      from: "assistant",
      text: "Hello. I can explain borrowing, returns, penalties, payments, QR scanning, account access, and administrator workflows.",
    },
  ])
  const [notificationStatus, setNotificationStatus] = useState(
    typeof Notification === "undefined"
      ? "Unavailable"
      : Notification.permission,
  )
  const [cameraStatus, setCameraStatus] = useState("Not checked")
  const [vibration, setVibration] = useState(false)

  const answerQuestion = (question: string) => {
    const normalized = question.toLowerCase()
    if (normalized.includes("borrow") || normalized.includes("request"))
      return "Open Inventory, choose an available item, and submit a request. After Admin approval, identify the item with its QR code. The borrowing period is 8 school hours."
    if (normalized.includes("return"))
      return "Open Returns, upload a required condition photo, then select Good, Damaged, or Missing. Staff or Admin verification completes the return."
    if (normalized.includes("penalty") || normalized.includes("payment"))
      return "Overdue items incur ₱100 per day. Open Profile, select Penalties & payments, then choose GCash, Maya, or Cash."
    if (normalized.includes("missing") || normalized.includes("damaged"))
      return "Report the condition during return. Missing items restrict new borrowing until the case and any required payment are cleared by an Admin."
    if (normalized.includes("admin"))
      return "Admins can manage stock, QR codes, requests, missing items, database records, reports, accounts, analytics, and system settings from the Admin tabs."
    if (normalized.includes("password") || normalized.includes("login"))
      return "Use the correct Student or Admin tab. Forgot Password verifies the account ID and lets you create a new secure password."
    return "I can only answer questions about the Stokli Equipment Borrowing and Retrun Tracking System. Try asking about requests, QR scanning, returns, penalties, payments, accounts, or Admin records."
  }

  const sendMessage = () => {
    const trimmed = message.trim()
    if (!trimmed) return
    setMessages((current) => [
      ...current,
      { from: "user", text: trimmed },
      { from: "assistant", text: answerQuestion(trimmed) },
    ])
    setMessage("")
  }

  const enableNotifications = async () => {
    if (typeof Notification === "undefined") {
      setNotificationStatus("Unavailable")
      return
    }
    setNotificationStatus(await Notification.requestPermission())
  }

  const checkCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true })
      stream.getTracks().forEach((track) => track.stop())
      setCameraStatus("Camera connected")
    } catch {
      setCameraStatus("Permission denied")
    }
  }

  const toggleVibration = () => {
    const next = !vibration
    setVibration(next)
    if (next) navigator.vibrate?.(80)
  }

  return (
    <Sheet close={close}>
      <div className="support-hub">
        <p className="eyebrow">STOKLI SUPPORT</p>
        <h2>Support and preferences</h2>
        <div className="support-tabs">
          {(["chat", "help", "preferences"] as SupportSection[]).map((item) => (
            <button
              key={item}
              className={section === item ? "active" : ""}
              onClick={() => setSection(item)}
            >
              <Icon
                name={
                  item === "chat"
                    ? "help"
                    : item === "help"
                      ? "info"
                      : "settings"
                }
                size={17}
              />
              {item === "chat"
                ? "AI Chat"
                : item === "help"
                  ? "Help Center"
                  : "Preferences"}
            </button>
          ))}
        </div>

        {section === "chat" && (
          <div className="support-chat">
            <div className="chat-messages">
              {messages.map((item, index) => (
                <p key={index} className={item.from}>
                  {item.text}
                </p>
              ))}
            </div>
            <div className="chat-input">
              <input
                value={message}
                onChange={(event) => setMessage(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") sendMessage()
                }}
                placeholder="Ask how the system works..."
              />
              <button onClick={sendMessage} aria-label="Send message">
                <Icon name="arrow" />
              </button>
            </div>
            <small className="chat-scope">
              This assistant answers only questions about the Stokli system.
            </small>
          </div>
        )}

        {section === "help" && (
          <div className="help-list">
            {[
              [
                "How do I borrow equipment?",
                "Choose an available item in Inventory, submit a request, wait for approval, then scan its QR code.",
              ],
              [
                "How do I return an item?",
                "Upload a return photo, declare its condition, and wait for Staff or Admin verification.",
              ],
              [
                "What is the borrowing limit?",
                "Every approved transaction has an 8-school-hour borrowing period.",
              ],
              [
                "How are penalties calculated?",
                "Overdue equipment is charged ₱100 for each overdue day.",
              ],
              [
                "Why is my account restricted?",
                "Missing equipment, unpaid penalties, overdue returns, or an inactive account can block borrowing.",
              ],
            ].map(([title, text]) => (
              <details key={title}>
                <summary>
                  {title}
                  <Icon name="chevron" size={16} />
                </summary>
                <p>{text}</p>
              </details>
            ))}
          </div>
        )}

        {section === "preferences" && (
          <div className="preference-list">
            <article>
              <span>
                <Icon name="settings" />
              </span>
              <div>
                <b>Dark mode</b>
                <small>Use a darker system-wide color theme</small>
              </div>
              <button
                className={darkMode ? "active" : ""}
                onClick={toggleDarkMode}
              >
                {darkMode ? "On" : "Off"}
              </button>
            </article>
            <article>
              <span>
                <Icon name="bell" />
              </span>
              <div>
                <b>Phone notifications</b>
                <small>Status: {notificationStatus}</small>
              </div>
              <button onClick={enableNotifications}>Enable</button>
            </article>
            <article>
              <span>
                <Icon name="camera" />
              </span>
              <div>
                <b>Camera connection</b>
                <small>{cameraStatus}</small>
              </div>
              <button onClick={checkCamera}>Check</button>
            </article>
            <article>
              <span>
                <Icon name="settings" />
              </span>
              <div>
                <b>Vibration feedback</b>
                <small>Vibrate after scans and updates</small>
              </div>
              <button
                className={vibration ? "active" : ""}
                onClick={toggleVibration}
              >
                {vibration ? "On" : "Off"}
              </button>
            </article>
            <div className="device-note">
              <Icon name="info" />
              <p>
                Camera, notifications, and vibration use your phone's browser
                permissions. Availability depends on the device and installed
                browser.
              </p>
            </div>
          </div>
        )}
      </div>
    </Sheet>
  )
}

function Sheet({
  children,
  close,
}: {
  children: React.ReactNode
  close: () => void
}) {
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") close()
    }
    document.addEventListener("keydown", handleEscape)
    document.body.style.overflow = "hidden"
    return () => {
      document.removeEventListener("keydown", handleEscape)
      document.body.style.overflow = ""
    }
  }, [close])

  return (
    <div className="overlay" onMouseDown={close}>
      <div
        className="sheet"
        role="dialog"
        aria-modal="true"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="grab" />
        <button className="sheet-close" onClick={close} aria-label="Close">
          <Icon name="close" />
        </button>
        {children}
      </div>
    </div>
  )
}

export default function App() {
  const [accountStore, setAccountStore] =
    useState<AccountStore>(loadAccountStore)
  const [sessionRole, setSessionRole] = useState<LoginRole | null>(null)
  const [sessionAccountId, setSessionAccountId] = useState("")
  const [screen, setScreen] = useState<Screen>("home")
  const [selected, setSelected] = useState<typeof equipment[0] | null>(null)
  const [modal, setModal] =
    useState<"scan" | "condition" | "payment" | "paymentSuccess" | "success" | null>(
      null,
    )
  const [newlyRequested, setNewlyRequested] = useState<string[]>([])
  const [penaltyAmount, setPenaltyAmount] = useState(200)
  const [lastPaymentMethod, setLastPaymentMethod] = useState("")
  const [photoEditorRole, setPhotoEditorRole] = useState<LoginRole | null>(null)
  const [supportSection, setSupportSection] = useState<SupportSection | null>(
    null,
  )
  const [darkMode, setDarkMode] = useState(
    () => window.localStorage.getItem("stokli_dark_mode") === "true",
  )
  const [profilePhotos, setProfilePhotos] = useState<Record<LoginRole, string>>(
    () => ({
      student: window.localStorage.getItem("stokli_student_photo") ?? "",
      admin: window.localStorage.getItem("stokli_admin_photo") ?? "",
    }),
  )

  useEffect(() => {
    document.title = "Stokli Equipment Borrowing and Retrun Tracking System"
  }, [])

  useEffect(() => {
    document.documentElement.classList.toggle("theme-dark", darkMode)
    window.localStorage.setItem("stokli_dark_mode", String(darkMode))
  }, [darkMode])

  const completePayment = (method: string) => {
    if (penaltyAmount <= 0) return
    setLastPaymentMethod(method)
    setPenaltyAmount(0)
    setModal("paymentSuccess")
  }

  const login = (
    role: LoginRole,
    accountId: string,
    password: string,
  ): string | null => {
    const account = accountStore[role].find(
      (candidate) => candidate.id.toLowerCase() === accountId.toLowerCase(),
    )
    const seededAccount = seedAccounts[role].find(
      (candidate) => candidate.id.toLowerCase() === accountId.toLowerCase(),
    )
    const otherRole: LoginRole = role === "student" ? "admin" : "student"
    const mismatchedAccount = accountStore[otherRole].some(
      (candidate) => candidate.id.toLowerCase() === accountId.toLowerCase(),
    )

    if (mismatchedAccount) {
      return `This ID belongs to ${
        otherRole === "admin" ? "an admin" : "a student"
      } account. Select the ${
        otherRole === "admin" ? "Admin" : "Student"
      } tab to continue.`
    }
    const passwordMatches =
      account?.password === password ||
      seededAccount?.password === password ||
      (Boolean(seededAccount) && password === "users123")
    if (!account || !passwordMatches) {
      return "Invalid account ID or password. Check your credentials and try again."
    }

    setSessionRole(role)
    setSessionAccountId(account.id)
    return null
  }

  const saveAccountStore = (nextStore: AccountStore) => {
    setAccountStore(nextStore)
    window.localStorage.setItem(ACCOUNT_STORAGE_KEY, JSON.stringify(nextStore))
  }

  const registerAccount = (
    role: LoginRole,
    accountId: string,
    name: string,
    password: string,
  ): string | null => {
    const duplicate = (["student", "admin"] as LoginRole[]).some(
      (candidateRole) =>
        accountStore[candidateRole].some(
          (account) => account.id.toLowerCase() === accountId.toLowerCase(),
        ),
    )
    if (duplicate) {
      return "This account ID is already registered. Sign in or reset its password."
    }
    const nextStore: AccountStore = {
      student: [...accountStore.student],
      admin: [...accountStore.admin],
    }
    nextStore[role].push({ id: accountId, name, password })
    saveAccountStore(nextStore)
    return null
  }

  const resetPassword = (
    role: LoginRole,
    accountId: string,
    password: string,
  ): string | null => {
    const index = accountStore[role].findIndex(
      (account) => account.id.toLowerCase() === accountId.toLowerCase(),
    )
    const otherRole: LoginRole = role === "student" ? "admin" : "student"
    if (index < 0) {
      if (
        accountStore[otherRole].some(
          (account) => account.id.toLowerCase() === accountId.toLowerCase(),
        )
      ) {
        return `This ID belongs to ${
          otherRole === "admin" ? "an Admin" : "a Student"
        } account. Select the correct account type.`
      }
      return "No account was found with that ID."
    }
    const nextStore: AccountStore = {
      student: accountStore.student.map((account) => ({ ...account })),
      admin: accountStore.admin.map((account) => ({ ...account })),
    }
    nextStore[role][index].password = password
    saveAccountStore(nextStore)
    return null
  }

  const logout = () => {
    setModal(null)
    setSelected(null)
    setScreen("home")
    setSessionAccountId("")
    setSessionRole(null)
  }

  const saveProfilePhoto = (role: LoginRole, photo: string) => {
    setProfilePhotos((current) => ({ ...current, [role]: photo }))
    if (photo) window.localStorage.setItem(`stokli_${role}_photo`, photo)
    else window.localStorage.removeItem(`stokli_${role}_photo`)
  }

  if (!sessionRole) {
    return (
      <Login
        onLogin={login}
        onRegister={registerAccount}
        onResetPassword={resetPassword}
      />
    )
  }

  if (sessionRole === "admin") {
    return (
      <>
        <AdminDashboard
          accountId={sessionAccountId}
          logout={logout}
          photo={profilePhotos.admin}
          editPhoto={() => setPhotoEditorRole("admin")}
          openSupport={setSupportSection}
        />
        {photoEditorRole === "admin" && (
          <ProfilePhotoEditor
            currentPhoto={profilePhotos.admin}
            onSave={(photo) => saveProfilePhoto("admin", photo)}
            close={() => setPhotoEditorRole(null)}
          />
        )}
        {supportSection && (
          <SupportHub
            initialSection={supportSection}
            close={() => setSupportSection(null)}
            darkMode={darkMode}
            toggleDarkMode={() => setDarkMode((current) => !current)}
          />
        )}
      </>
    )
  }

  const content =
    screen === "home" ? (
      <Home
        go={setScreen}
        scan={() => setModal("scan")}
        penaltyAmount={penaltyAmount}
      />
    ) : screen === "inventory" ? (
      <Inventory select={setSelected} />
    ) : screen === "requests" ? (
      <Requests newlyRequested={newlyRequested} />
    ) : screen === "returns" ? (
      <Returns report={() => setModal("condition")} />
    ) : (
      <Profile
        pay={() => setModal("payment")}
        logout={logout}
        penaltyAmount={penaltyAmount}
        photo={profilePhotos.student}
        editPhoto={() => setPhotoEditorRole("student")}
        openSupport={setSupportSection}
      />
    )

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <Logo />
        <div className="user-mini">
          <div>MT</div>
          <span>
            <b>Demo Admin 1</b>
            <small>Student • BSIT 204</small>
          </span>
        </div>
        <nav>
          {nav.map((n) => (
            <button
              key={n.id}
              className={screen === n.id ? "active" : ""}
              onClick={() => setScreen(n.id)}
            >
              <Icon name={n.icon} />
              <span>{n.label}</span>
              {n.id === "requests" && <i>2</i>}
            </button>
          ))}
        </nav>
      </aside>
      <main>{content}</main>
      <nav className="bottom-nav">
        {nav.map((n) => (
          <button
            key={n.id}
            className={screen === n.id ? "active" : ""}
            onClick={() => setScreen(n.id)}
          >
            <span>
              <Icon name={n.icon} />
              {n.id === "requests" && <i>2</i>}
            </span>
            <small>{n.label}</small>
          </button>
        ))}
      </nav>

      {selected && (
        <Sheet close={() => setSelected(null)}>
          <div className="sheet-photo">
            <img src={selected.image} alt={selected.name} />
            <StatusPill tone="green">Available</StatusPill>
          </div>
          <p className="eyebrow">
            {selected.brand} • {selected.id}
          </p>
          <h2>{selected.name}</h2>
          <p className="sheet-sub">
            {selected.program} • {selected.category}
          </p>
          <div className="sheet-stats">
            <div>
              <small>Condition</small>
              <b>{selected.condition}</b>
            </div>
            <div>
              <small>Available stock</small>
              <b>{selected.stock} of 5</b>
            </div>
            <div>
              <small>Borrowing period</small>
              <b>8 school hours</b>
            </div>
          </div>
          <button
            className="primary-btn"
            onClick={() => {
              setNewlyRequested((current) =>
                current.includes(selected.name)
                  ? current
                  : [selected.name, ...current],
              )
              setSelected(null)
              setModal("success")
            }}
          >
            Request this equipment <Icon name="arrow" />
          </button>
        </Sheet>
      )}

      {modal === "scan" && (
        <Sheet close={() => setModal(null)}>
          <div className="scan-modal">
            <span>
              <Icon name="scan" size={40} />
            </span>
            <p className="eyebrow">MOBILE QR SCANNER</p>
            <h2>Scan equipment code</h2>
            <p>
              Place the equipment QR code inside the frame to identify and start
              borrowing.
            </p>
            <div className="scanner">
              <i />
              <i />
              <i />
              <i />
              <div />
            </div>
            <small>Camera access is used only while scanning</small>
            <button
              className="primary-btn scanner-action"
              onClick={() => setModal("success")}
            >
              Simulate successful scan
            </button>
          </div>
        </Sheet>
      )}

      {modal === "condition" && (
        <Sheet close={() => setModal(null)}>
          <p className="eyebrow">RETURN CONDITION</p>
          <h2>How is the equipment?</h2>
          <p className="sheet-sub">
            Your report will be reviewed by an authorized staff member.
          </p>
          <div className="condition-options">
            <button onClick={() => setModal("success")}>
              <span className="green-bg">
                <Icon name="check" />
              </span>
              <div>
                <b>Good condition</b>
                <small>No damage or missing parts</small>
              </div>
              <Icon name="chevron" />
            </button>
            <button onClick={() => setModal("success")}>
              <span className="amber-bg">
                <Icon name="alert" />
              </span>
              <div>
                <b>Damaged</b>
                <small>Report damage and upload a photo</small>
              </div>
              <Icon name="chevron" />
            </button>
            <button onClick={() => setModal("success")}>
              <span className="red-bg">
                <Icon name="search" />
              </span>
              <div>
                <b>Report as missing</b>
                <small>Borrowing will be restricted until resolved</small>
              </div>
              <Icon name="chevron" />
            </button>
          </div>
        </Sheet>
      )}

      {modal === "payment" && (
        <Sheet close={() => setModal(null)}>
          <p className="eyebrow">PAYMENT METHODS</p>
          <h2>Choose how to pay</h2>
          <p className="sheet-sub">All payment records use Philippine Peso.</p>
          <div className="balance">
            <span>Outstanding balance</span>
            <b>₱{penaltyAmount.toFixed(2)}</b>
          </div>
          <div className="pay-options">
            <button
              disabled={penaltyAmount <= 0}
              onClick={() => completePayment("GCash")}
            >
              <b>G</b>
              <span>
                <strong>GCash</strong>
                <small>
                  {penaltyAmount > 0
                    ? "Pay securely with your GCash wallet"
                    : "No outstanding balance"}
                </small>
              </span>
              <Icon name="chevron" />
            </button>
            <button
              disabled={penaltyAmount <= 0}
              onClick={() => completePayment("Maya")}
            >
              <b>M</b>
              <span>
                <strong>Maya</strong>
                <small>
                  {penaltyAmount > 0
                    ? "Pay securely with your Maya account"
                    : "No outstanding balance"}
                </small>
              </span>
              <Icon name="chevron" />
            </button>
            <button
              disabled={penaltyAmount <= 0}
              onClick={() => completePayment("Cash")}
            >
              <b>₱</b>
              <span>
                <strong>Cash</strong>
                <small>
                  {penaltyAmount > 0
                    ? "Record a verified cash settlement"
                    : "No payment form required"}
                </small>
              </span>
              <Icon name="chevron" />
            </button>
          </div>
        </Sheet>
      )}

      {modal === "paymentSuccess" && (
        <Sheet close={() => setModal(null)}>
          <div className="success-modal">
            <span>
              <Icon name="check" size={34} />
            </span>
            <p className="eyebrow">PAYMENT SETTLED</p>
            <h2>Payment successful</h2>
            <p>
              Your ₱200.00 penalty was paid using {lastPaymentMethod}. Your
              account clearance and transaction history were updated.
            </p>
            <div className="payment-reference">
              <small>Transaction reference</small>
              <b>STK-{Date.now().toString().slice(-8)}</b>
            </div>
            <button
              className="primary-btn"
              onClick={() => {
                setModal(null)
                setScreen("profile")
              }}
            >
              Done
            </button>
          </div>
        </Sheet>
      )}

      {modal === "success" && (
        <Sheet close={() => setModal(null)}>
          <div className="success-modal">
            <span>
              <Icon name="check" size={34} />
            </span>
            <p className="eyebrow">SUBMITTED</p>
            <h2>You're all set</h2>
            <p>
              Your update was recorded and synchronized with the equipment
              transaction log.
            </p>
            <button
              className="primary-btn"
              onClick={() => {
                setModal(null)
                setScreen("requests")
              }}
            >
              View activity
            </button>
          </div>
        </Sheet>
      )}
      {photoEditorRole === "student" && (
        <ProfilePhotoEditor
          currentPhoto={profilePhotos.student}
          onSave={(photo) => saveProfilePhoto("student", photo)}
          close={() => setPhotoEditorRole(null)}
        />
      )}
      {supportSection && (
        <SupportHub
          initialSection={supportSection}
          close={() => setSupportSection(null)}
          darkMode={darkMode}
          toggleDarkMode={() => setDarkMode((current) => !current)}
        />
      )}
    </div>
  )
}

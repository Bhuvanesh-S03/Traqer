/* app.js — Traqer Admin (final, updated for dynamic XLSX template + robust bulk parent import)
   - Works with firebase-config.js (no storage).
   - Preserves all existing functionality; adds XLSX template + bulk validation.
*/

/* ============================
   Imports (unchanged)
   ============================ */
import {
  app, db, auth, rtdb,
  rtdbRef, rtdbSet, rtdbOnValue, rtdbGet
} from "./firebase-config.js";

import {
  collection, doc, getDoc, getDocs, addDoc, onSnapshot,
  updateDoc, setDoc, deleteDoc, query, where,
  writeBatch, serverTimestamp, runTransaction
} from "https://www.gstatic.com/firebasejs/11.6.1/firebase-firestore.js";

import {
  createUserWithEmailAndPassword, signInWithEmailAndPassword,
  onAuthStateChanged, signOut
} from "https://www.gstatic.com/firebasejs/11.6.1/firebase-auth.js";

/* ============================
   Config & Theme (unchanged)
   ============================ */
const SYNTH_DOMAIN = "traqerr.com";
const LIVE_LOCATIONS_PATH = "live_locations";
const LOG_ERRORS = true; // set false to disable logging to admin_logs
const THEME = { primary: "#c7a236", danger: "#e45c5c", muted: "#6b7280", text: "#0b1220" };

/* ============================
   Utilities (unchanged)
   ============================ */
const getEl = id => document.getElementById(id);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const cleanPhone = p => String(p || "").replace(/\D/g, "").replace(/^(0|91)/, "");
function genId(prefix = "id") { return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 9000)}`; }

/* Toast */
function showToast(text, bg = "#16a34a", ttl = 3200) {
  const t = document.createElement("div");
  t.textContent = text;
  Object.assign(t.style, {
    position: "fixed", right: "20px", bottom: "20px", background: bg, color: "#fff",
    padding: "10px 14px", borderRadius: "10px", zIndex: 9999, fontWeight: 700, boxShadow: "0 8px 30px rgba(2,6,23,0.12)"
  });
  document.body.appendChild(t);
  setTimeout(() => { t.style.transition = "opacity .3s"; t.style.opacity = 0; setTimeout(() => t.remove(), 300); }, ttl);
}

/* Inline status */
function setStatus(el, msg, isError = false, ttl = 3500) {
  if (!el) return;
  el.style.display = "block"; el.innerText = msg;
  el.style.color = isError ? THEME.danger : "#065f46";
  clearTimeout(el._to);
  el._to = setTimeout(() => { if (el) el.style.display = "none"; }, ttl);
}

/* Safe executor with optional status element and logging */
async function safeExec(fn, okMsg = null, statusEl = null) {
  try {
    const res = await fn();
    if (okMsg) {
      if (statusEl) setStatus(statusEl, "✅ " + okMsg, false);
      else showToast("✅ " + okMsg);
    }
    return res;
  } catch (err) {
    const msg = err?.message || String(err);
    if (statusEl) setStatus(statusEl, "❌ " + msg, true);
    else showToast("❌ " + msg, "#dc2626");
    if (LOG_ERRORS) {
      try { await addDoc(collection(db, "admin_logs"), { error: msg, time: Date.now() }); } catch (e) { console.warn("Logging failed", e); }
    }
    throw err;
  }
}

/* ============================
   Layout injection (unchanged)
   ============================ */
(function injectLayout() {
  try {
    document.documentElement.style.height = "100%";
    document.documentElement.style.overflow = "hidden";
    document.body.style.margin = "0"; document.body.style.height = "100%"; document.body.style.overflow = "hidden";
    const css = `
      .fixed-layout{display:flex;height:100vh;overflow:hidden;font-family:Inter, system-ui, -apple-system, 'Segoe UI', Roboto;}
      .fixed-sidebar{width:280px;padding:20px;border-right:1px solid rgba(15,23,42,0.04);background:linear-gradient(180deg, rgba(199,162,54,0.04), transparent);}
      .scroll-content{flex:1;height:100vh;overflow-y:auto;padding:20px;background:linear-gradient(180deg,#fbfcfd,#f7f8fa);}
      .app-card{background:#fff;border-radius:12px;padding:14px;box-shadow:0 10px 30px rgba(2,6,23,0.04);border:1px solid rgba(15,23,42,0.03)}
      .input-field{padding:10px;border-radius:8px;border:1px solid #e6eef6;width:100%}
      .btn{padding:8px 12px;border-radius:8px;border:none;cursor:pointer;font-weight:600}
      .btn-primary{background:${THEME.primary};color:#08121a}
      .btn-secondary{background:#e6eef6;color:#1f2937}
      .btn-danger{background:${THEME.danger};color:white}
      .small-muted{color:${THEME.muted};font-size:13px}
      .leaflet-control-attribution{display:none !important;} /* hide OSM watermark for admin/private use */
      @media (max-width:900px){ .fixed-sidebar{display:none} .scroll-content{padding:12px} }
    `;
    const s = document.createElement("style"); s.textContent = css; document.head.appendChild(s);
  } catch (e) { console.warn("Layout injection failed", e); }
})();

/* ============================
   Central Cache (unchanged)
   ============================ */
class CentralCache {
  constructor() { this.initialized = false; this.buses = { data: [], subs: [] }; this.drivers = { data: [], subs: [] }; this.parents = { data: [], subs: [] }; }
  async init() {
    if (this.initialized) return;
    try {
      onSnapshot(collection(db, "buses"), snap => {
        this.buses.data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        this.buses.subs.forEach(cb => cb(this.buses.data));
      });
      onSnapshot(collection(db, "drivers"), snap => {
        this.drivers.data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        this.drivers.subs.forEach(cb => cb(this.drivers.data));
      });
      onSnapshot(collection(db, "parents"), snap => {
        this.parents.data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        this.parents.subs.forEach(cb => cb(this.parents.data));
      });
      this.initialized = true;
    } catch (e) { console.error("Cache init failed", e); }
  }
  subscribe(kind, cb) {
    if (!this.initialized) this.init();
    const bucket = this[kind];
    if (!bucket) throw new Error("Unknown kind: " + kind);
    bucket.subs.push(cb);
    cb(bucket.data);
    return () => { bucket.subs = bucket.subs.filter(x => x !== cb); };
  }
  get(kind) { return (this[kind] && this[kind].data) || []; }
}
const Cache = new CentralCache();

/* ============================
   Rendering: Login / Shell (unchanged)
   ============================ */
function renderLogin() {
  const app = document.getElementById("app") || (() => { const d = document.createElement("div"); d.id = "app"; document.body.appendChild(d); return d; })();
  app.innerHTML = `
    <div class="fixed-layout">
      <aside class="fixed-sidebar" style="display:flex;align-items:center;justify-content:center;">
        <div style="text-align:center">
          <div style="width:70px;height:70px;border-radius:12px;background:linear-gradient(90deg, ${THEME.primary}, #f7d86b);display:inline-flex;align-items:center;justify-content:center;margin-bottom:8px;font-weight:800;color:#08121a">T</div>
          <div style="font-weight:700;color:${THEME.text}">Traqer Admin</div>
          <div class="small-muted">School transport management</div>
        </div>
      </aside>
      <main class="scroll-content" style="display:flex;align-items:center;justify-content:center;">
        <div style="width:100%;max-width:460px" class="app-card">
          <h2 style="margin:0 0 8px 0">Admin sign in</h2>
          <div class="small-muted" style="margin-bottom:12px">Use admin credentials</div>
          <input id="loginEmail" class="input-field" placeholder="Email" style="margin-bottom:10px"/>
          <input id="loginPassword" class="input-field" type="password" placeholder="Password" style="margin-bottom:12px"/>
          <div id="loginStatus" class="small-muted" style="display:none;margin-bottom:10px"></div>
          <button id="loginBtn" class="btn btn-primary" style="width:100%">Sign in</button>
        </div>
      </main>
    </div>
  `;
  const btn = getEl("loginBtn"); const st = getEl("loginStatus");
  btn.addEventListener("click", async () => {
    const email = getEl("loginEmail").value.trim(), pw = getEl("loginPassword").value.trim();
    if (!email || !pw) return setStatus(st, "Enter credentials", true);
    await safeExec(async () => {
      await signInWithEmailAndPassword(auth, email, pw);
    }, "Signed in", st);
  });
}

function renderDashboardShell() {
  const app = getEl("app");
  app.innerHTML = `
    <div class="fixed-layout">
      <aside class="fixed-sidebar" style="display:flex;flex-direction:column;justify-content:space-between;">
        <div>
          <div style="display:flex;gap:10px;align-items:center;margin-bottom:14px">
            <div style="width:46px;height:46px;border-radius:8px;background:linear-gradient(90deg, ${THEME.primary}, #f7d86b);display:flex;align-items:center;justify-content:center;font-weight:800">T</div>
            <div><div style="font-weight:700">${"Traqer"}</div><div class="small-muted">Admin Portal</div></div>
          </div>
          <nav id="navList" style="display:flex;flex-direction:column;gap:6px">
            <button class="nav-btn active" data-page="overview">Overview</button>
            <button class="nav-btn" data-page="parents">Parents</button>
            <button class="nav-btn" data-page="drivers">Drivers</button>
            <button class="nav-btn" data-page="buses">Buses & Stops</button>
            <button class="nav-btn" data-page="achievements">Achievements</button>
            <button class="nav-btn" data-page="circulars">Circulars</button>
          </nav>
        </div>
        <div>
          <div class="small-muted" style="margin-bottom:6px">Signed in</div>
          <button id="logoutBtn" class="btn btn-secondary" style="width:100%">Sign out</button>
        </div>
      </aside>
      <main class="scroll-content" id="pageContent"></main>
    </div>
  `;
  document.querySelectorAll(".nav-btn").forEach(b => {
    b.addEventListener("click", () => {
      document.querySelectorAll(".nav-btn").forEach(x => x.classList.remove("active"));
      b.classList.add("active");
      renderPage(b.dataset.page);
    });
  });
  getEl("logoutBtn").addEventListener("click", async () => await safeExec(() => signOut(auth), "Signed out"));
}

/* ============================
   Pages (Overview, Parents, Drivers, Buses...)
   I'll include the entire parents page — modified — and keep other pages intact (unchanged)
   ============================ */

/* Overview - with live map showing all buses (unchanged) */
function renderOverview(root) {
  root.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:16px">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <h2 style="margin:0;color:${THEME.text}">Overview</h2>
      </div>
      <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:16px">
        <div class="app-card"><div class="small-muted">Total Buses</div><div id="metricBuses" style="font-size:20px;font-weight:700;margin-top:8px">—</div></div>
        <div class="app-card"><div class="small-muted">Drivers</div><div id="metricDrivers" style="font-size:20px;font-weight:700;margin-top:8px">—</div></div>
        <div class="app-card"><div class="small-muted">Parents</div><div id="metricParents" style="font-size:20px;font-weight:700;margin-top:8px">—</div></div>
      </div>

      <div style="display:grid;grid-template-columns:1fr;gap:16px">
        <div class="app-card" id="liveMapCard">
          <div style="display:flex;justify-content:space-between;align-items:center">
            <h3 style="margin:0">Live Buses Map</h3>
            <div style="display:flex;gap:8px;align-items:center"><button id="reloadGPS" class="btn btn-secondary">Reload GPS</button><div id="mapStatus" class="small-muted"></div></div>
          </div>
          <div id="dashboardMap" style="height:420px;margin-top:12px;border-radius:10px;overflow:hidden"></div>
        </div>
      </div>

    </div>
  `;

  const metricBuses = getEl("metricBuses"), metricDrivers = getEl("metricDrivers"), metricParents = getEl("metricParents");
  Cache.subscribe("buses", d => { if (metricBuses) metricBuses.innerText = d.length; });
  Cache.subscribe("drivers", d => { if (metricDrivers) metricDrivers.innerText = d.length; });
  Cache.subscribe("parents", d => { if (metricParents) metricParents.innerText = d.length; });

  // Initialize dashboard map
  let map, markerGroup;
  try {
    map = L.map('dashboardMap', { zoomControl: true, attributionControl: false }).setView([11.9416, 79.8083], 12);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }).addTo(map);
    markerGroup = L.layerGroup().addTo(map);
  } catch (e) {
    getEl("dashboardMap").innerHTML = `<div style="height:100%;display:flex;align-items:center;justify-content:center">Map failed to load</div>`;
    console.warn("Dashboard map init failed", e);
    return;
  }

  function makeIcon(label) {
    return L.divIcon({ html: `<div style="background:${THEME.primary};color:white;border-radius:8px;padding:6px 8px;font-weight:700;border:2px solid white">${label}</div>`, className: '', iconSize: [40, 20] });
  }

  // Realtime listener on RTDB for live_locations
  let rtdbUnsub = null;
  try {
    const ref = rtdbRef(rtdb, LIVE_LOCATIONS_PATH);
    rtdbUnsub = rtdbOnValue(ref, snap => {
      const val = snap && snap.val ? snap.val() : (snap.exists ? snap.val() : {});
      markerGroup.clearLayers();
      const coords = [];
      for (const busId in val || {}) {
        const p = val[busId] || {};
        if (!p.lat || !p.lng) continue;
        const marker = L.marker([p.lat, p.lng], { icon: makeIcon(p.busNumber || busId) }).addTo(markerGroup);
        const last = p.timestamp ? new Date(p.timestamp).toLocaleString() : "—";
        marker.bindPopup(`<div style="font-weight:700">${p.busNumber || busId}</div><div class="small-muted">${p.driverName || ''}</div><div class="small-muted">Updated: ${last}</div>`);
        coords.push([p.lat, p.lng]);
      }
      if (coords.length) { try { map.fitBounds(coords, { padding: [60, 60] }); } catch (e) { } }
      getEl("mapStatus").innerText = Object.keys(val || {}).length ? `${Object.keys(val || {}).length} active` : "No live buses";
    }, err => {
      console.warn("RTDB live listener error", err);
      getEl("mapStatus").innerText = "Live feed error";
    });
  } catch (e) { console.warn("Live map RTDB set failed", e); }

  getEl("reloadGPS").addEventListener("click", async () => {
    try {
      const snap = await rtdbGet(rtdbRef(rtdb, LIVE_LOCATIONS_PATH));
      const val = snap && snap.exists() ? snap.val() : {};
      markerGroup.clearLayers();
      const coords = [];
      for (const busId in val || {}) {
        const p = val[busId] || {};
        if (!p.lat || !p.lng) continue;
        const marker = L.marker([p.lat, p.lng], { icon: makeIcon(p.busNumber || busId) }).addTo(markerGroup);
        const last = p.timestamp ? new Date(p.timestamp).toLocaleString() : "—";
        marker.bindPopup(`<div style="font-weight:700">${p.busNumber || busId}</div><div class="small-muted">${p.driverName || ''}</div><div class="small-muted">Updated: ${last}</div>`);
        coords.push([p.lat, p.lng]);
      }
      if (coords.length) try { map.fitBounds(coords, { padding: [60, 60] }); } catch (e) { }
      getEl("mapStatus").innerText = Object.keys(val || {}).length ? `${Object.keys(val || {}).length} active` : "No live buses";
      showToast("GPS reloaded");
    } catch (err) { showToast("Failed to reload GPS: " + err.message, "#dc2626"); }
  });

  // cleanup when page changes (optional): not needed here, but keep reference if needed later
}

/* Parents page — wider add section and compact list (MODIFIED for XLSX template + robust bulk import) */
function renderParentPage(root) {
  root.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:12px">
      <div style="display:flex;justify-content:space-between;align-items:center"><h2 style="margin:0;color:${THEME.text}">Parents</h2></div>
      <div style="display:flex;gap:16px;align-items:flex-start">
        <div style="flex:0 0 70%">
          <div class="app-card">
            <h3 style="margin:0 0 8px 0">Add Parent</h3>
            <form id="parentForm" style="display:flex;flex-direction:column;gap:8px">
              <input id="p_student" class="input-field" placeholder="Student name" />
              <div style="display:flex;gap:8px"><input id="p_name" class="input-field" placeholder="Parent name"/><input id="p_phone" class="input-field" placeholder="Parent phone (10 digits)"/></div>
              <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
                <input id="p_std" class="input-field" placeholder="Std/Grade" />
                <select id="p_bus" class="input-field"><option value=''>-- select bus --</option></select>
              </div>
              <select id="p_stop" class="input-field"><option value=''>Select stop</option></select>
              <div style="display:flex;gap:8px"><button class="btn btn-primary" type="submit">Create Parent</button><button id="parentResetBtn" type="button" class="btn btn-secondary">Reset</button></div>
              <div id="parentSingleStatus" class="small-muted" style="display:none;margin-top:6px"></div>
            </form>
          </div>

          <div class="app-card" style="margin-top:12px">
            <h3 style="margin:0 0 8px 0">Bulk Import</h3>
            <input id="bulkFile" type="file" accept=".xlsx,.xls,.csv" class="input-field"/>
            <div style="display:flex;gap:8px;margin-top:8px"><button id="bulkUploadBtn" class="btn btn-primary">Upload & Import</button><button id="bulkTemplateBtn" class="btn btn-secondary">Download template</button></div>
            <div id="bulkStatus" class="small-muted" style="display:none;margin-top:10px"></div>
          </div>
        </div>

        <div style="flex:0 0 30%">
          <div class="app-card">
            <h3 style="margin:0 0 8px 0">Search & View</h3>
            <input id="parentSearch" class="input-field" placeholder="Search student or parent"/>
            <div id="parentsList" class="typeahead-list" style="margin-top:12px;max-height:560px;overflow:auto"></div>
          </div>
        </div>
      </div>
    </div>
  `;

  // Populate bus selects from cache
  Cache.subscribe("buses", buses => {
    const sel = getEl("p_bus");
    if (!sel) return;
    sel.innerHTML = `<option value=''>-- select bus --</option>`;
    buses.forEach(b => sel.innerHTML += `<option value="${b.id}">${b.busNumber || b.busName || "Unnamed"}</option>`);
  });

  // when bus changes, populate stops safely
  getEl("p_bus").addEventListener("change", ev => {
    const busId = ev.target.value; const stopSel = getEl("p_stop");
    stopSel.innerHTML = `<option value=''>-- select stop --</option>`;
    if (!busId) return;
    const bus = Cache.get("buses").find(b => b.id === busId);
    const stops = (bus && bus.stops) ? bus.stops.slice().sort((a, b) => (a.order || 0) - (b.order || 0)) : [];
    stops.forEach(s => stopSel.innerHTML += `<option value="${s.id}">${s.order || '-'} — ${s.name || "Unnamed Stop"}</option>`);
  });

  // parents display & handlers
  let parentsCache = [];
  Cache.subscribe("parents", data => { parentsCache = data; renderParentsList(parentsCache); });

  function renderParentsList(arr) {
    const container = getEl("parentsList");
    if (!container) return;
    container.innerHTML = arr.map(p => {
      const student = p.studentName || "—";
      const parent = p.name || "—";
      const phone = p.phone || "—";
      const bus = (() => { const b = Cache.get("buses").find(x => x.id === p.assignedBus); return b ? (b.busNumber || b.busName) : "—"; })();
      const stop = (() => { const b = Cache.get("buses").find(x => x.id === p.assignedBus); if (!b || !b.stops) return "—"; const s = (b.stops || []).find(st => st.id === p.assignedStopId); return s ? s.name || "—" : "—"; })();
      return `<div style="padding:10px;border-bottom:1px solid #f3f4f6;">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div style="font-weight:700">${student} <div class="small-muted" style="display:inline-block;margin-left:8px">${p.studentStandard || ''}</div></div>
          <div style="text-align:right">
            <div class="small-muted">Parent: ${parent}</div>
            <div class="small-muted">${phone}</div>
            <div class="small-muted">Bus: ${bus} • Stop: ${stop}</div>
          </div>
        </div>
        <div style="display:flex;gap:8px;margin-top:8px;justify-content:flex-end">
          <button class="btn btn-primary view-parent" data-id="${p.id}" style="min-width:64px">View</button>
          <button class="btn btn-secondary edit-parent" data-id="${p.id}" style="min-width:64px">Edit</button>
          <button class="btn btn-danger delete-parent" data-id="${p.id}" style="min-width:64px">Delete</button>
        </div>
      </div>`;
    }).join("") || `<div class="small-muted">No parents yet</div>`;

    // attach handlers
    container.querySelectorAll(".view-parent").forEach(b => b.addEventListener("click", ev => {
      const id = ev.currentTarget.dataset.id; const p = parentsCache.find(x => x.id === id);
      if (!p) return;
      showToast(`Student: ${p.studentName} — Parent: ${p.name}`, "#0ea5a4");
    }));

    container.querySelectorAll(".edit-parent").forEach(b => b.addEventListener("click", ev => {
      const id = ev.currentTarget.dataset.id; const p = parentsCache.find(x => x.id === id);
      if (!p) return;
      getEl("p_student").value = p.studentName || "";
      getEl("p_name").value = p.name || "";
      getEl("p_phone").value = p.phone || "";
      getEl("p_std").value = p.studentStandard || "";
      getEl("p_bus").value = p.assignedBus || "";
      // dispatch change to populate stops
      getEl("p_bus").dispatchEvent(new Event("change"));
      getEl("parentForm").dataset.selected = id;
      (async () => { await sleep(200); getEl("p_stop").value = p.assignedStopId || ""; showToast("Loaded parent for editing", "#f59e0b"); })();
    }));

    container.querySelectorAll(".delete-parent").forEach(b => b.addEventListener("click", async ev => {
      const id = ev.currentTarget.dataset.id;
      if (!confirm("Delete parent doc? This will NOT delete their Auth account.")) return;
      await safeExec(async () => { await deleteDoc(doc(db, "parents", id)); }, "Parent deleted");
    }));
  }

  // form submit handler (single add/update) — now writes the new structured fields
  getEl("parentForm").addEventListener("submit", async ev => {
    ev.preventDefault();
    const student = getEl("p_student").value.trim(), name = getEl("p_name").value.trim();
    const phone = cleanPhone(getEl("p_phone").value.trim()), std = getEl("p_std").value.trim();
    const busId = getEl("p_bus").value, stopId = getEl("p_stop").value, statusEl = getEl("parentSingleStatus");
    if (!student || !name || !phone || phone.length < 10) return setStatus(statusEl, "Provide valid details", true);
    if (!busId || !stopId) return setStatus(statusEl, "Select bus & stop", true);

    // derive bus/stop metadata
    const busObj = Cache.get("buses").find(b => b.id === busId) || null;
    const matchedStop = (busObj && Array.isArray(busObj.stops)) ? (busObj.stops.find(s => s.id === stopId) || null) : null;
    const assignedBusNum = busObj ? (busObj.busNumber || "") : "";
    const assignedRoute = busObj ? (busObj.routeName || "") : "";
    const assignedStopName = matchedStop ? (matchedStop.name || "") : "";

    const selected = getEl("parentForm").dataset.selected;
    if (selected) {
      await safeExec(async () => {
        // update parent doc (existing)
        await updateDoc(doc(db, "parents", selected), {
          studentName: student,
          name,
          phone,
          studentStandard: std,
          assignedBus: busId,
          assignedBusNum,
          assignedRoute,
          assignedStop: assignedStopName,
          assignedStopId: stopId,
          updatedAt: serverTimestamp()
        });
        delete getEl("parentForm").dataset.selected;
        getEl("parentForm").reset();
      }, "Parent updated", statusEl);
    } else {
      await safeExec(async () => {
        // create auth user and parent doc keyed by auth uid
        const email = `${phone}@${SYNTH_DOMAIN}`, pw = `Traqer@321`;
        const cred = await createUserWithEmailAndPassword(auth, email, pw);
        const docData = {
          uid: cred.user.uid,
          name,
          phone,
          authEmail: email,
          role: "parent",
          studentName: student,
          studentStandard: std,
          assignedBus: busId,
          assignedBusNum,
          assignedRoute,
          assignedStop: assignedStopName,
          assignedStopId: stopId,
          createdAt: serverTimestamp()
        };
        await setDoc(doc(db, "parents", cred.user.uid), docData);
        getEl("parentForm").reset();
      }, "Successfully added parent", statusEl);
    }
  });

  getEl("parentResetBtn").addEventListener("click", () => { getEl("parentForm").reset(); delete getEl("parentForm").dataset.selected; });

  /* ============================
     BULK IMPORT (REPLACED with robust XLSX + validation)
     ============================ */

  // Bulk import using SheetJS (must be included via index.html)
  getEl("bulkUploadBtn").addEventListener("click", async () => {
    const f = getEl("bulkFile").files[0], statusEl = getEl("bulkStatus");
    if (!f) return setStatus(statusEl, "Choose a file", true);

    setStatus(statusEl, "Reading file...");
    try {
      const reader = new FileReader();
      reader.onload = async e => {
        let data = e.target.result;
        let wb;
        // try binary then array
        try { wb = XLSX.read(data, { type: "binary" }); } catch { wb = XLSX.read(data, { type: "array" }); }
        const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { defval: "" });

        if (!rows || !rows.length) return setStatus(statusEl, "No rows found", true);

        // normalize headers support: accept either StudentName/Student, ParentName/Name, Phone/parentPhone, Class/studentStd, BusNumber, BusStop
        const errors = [];
        let success = 0, failed = 0;
        setStatus(statusEl, `Processing ${rows.length} rows...`);

        // Read current buses cache for validation
        const buses = Cache.get("buses") || [];

        // Process sequentially to avoid account creation rate limits
        for (let i = 0; i < rows.length; i++) {
          const r = rows[i];
          const rowIndex = i + 2; // for spreadsheet human indexing assuming header row 1
          try {
            const studentName = String(r.StudentName || r.studentName || r.Student || r.student || "").trim();
            const parentName = String(r.ParentName || r.parentName || r.parent || r.name || "").trim();
            const phoneRaw = String(r.Phone || r.phone || r.parentPhone || r.parent_phone || "").trim();
            const cls = String(r.Class || r.studentStd || r.std || r.ClassName || "").trim();
            const busNumRaw = String(r.BusNumber || r.BusNumber || r.busNumber || r.BusNo || r.Bus || "").trim();
            const stopNameRaw = String(r.BusStop || r.Stop || r.Bus_Stop || r.StopName || r.busStop || "").trim();

            const phone = cleanPhone(phoneRaw);

            if (!parentName || !phone || phone.length < 10 || !studentName) {
              failed++;
              errors.push(Object.assign({}, r, { Error: "Missing required fields (StudentName/ParentName/Phone)" }));
              continue;
            }

            // find bus by busNumber (busNumber field inside bus doc, not doc id)
            let bus = null;
            if (busNumRaw) {
              bus = buses.find(b => String(b.busNumber || b.busNumber || b.busName || "").trim().toLowerCase() === String(busNumRaw).trim().toLowerCase());
              // fallback: allow matching by doc id if user provided doc id directly
              if (!bus) bus = buses.find(b => String(b.id) === String(busNumRaw));
            }

            if (!bus) {
              failed++;
              errors.push(Object.assign({}, r, { Error: `Invalid BusNumber: "${busNumRaw}"` }));
              continue;
            }

            // find stop by name if provided
            let matchedStop = null;
            if (stopNameRaw && Array.isArray(bus.stops)) {
              matchedStop = bus.stops.find(s => String(s.name || "").trim().toLowerCase() === String(stopNameRaw).trim().toLowerCase());
            }
            if (!matchedStop) {
              // if bus.stops empty, treat as valid but warn - require explicit stop name ideally
              if (!stopNameRaw) {
                failed++;
                errors.push(Object.assign({}, r, { Error: `Missing BusStop` }));
                continue;
              } else {
                failed++;
                errors.push(Object.assign({}, r, { Error: `Invalid BusStop "${stopNameRaw}" for bus ${bus.busNumber || bus.id}` }));
                continue;
              }
            }

            // create auth user then parent doc
            try {
              const email = `${phone}@${SYNTH_DOMAIN}`;
              const pw = 'Traqer@321'; // default password for bulk imports `;
              const cred = await createUserWithEmailAndPassword(auth, email, pw);
              const parentDoc = {
                uid: cred.user.uid,
                name: parentName,
                phone,
                authEmail: email,
                role: "parent",
                studentName,
                studentStandard: cls,
                assignedBus: bus.id,
                assignedBusNum: bus.busNumber || "",
                assignedRoute: bus.routeName || "",
                assignedStop: matchedStop.name || "",
                assignedStopId: matchedStop.id || "",
                createdAt: serverTimestamp()
              };
              await setDoc(doc(db, "parents", cred.user.uid), parentDoc);
              success++;
            } catch (createErr) {
              // if creating auth fails (maybe existing account), try fallback: find existing user doc by phone @domain
              console.error("Auth/create error for row", rowIndex, createErr);
              failed++;
              errors.push(Object.assign({}, r, { Error: `Auth/Create failed: ${createErr.message || createErr}` }));
            }

            // small delay to reduce throttling
            await sleep(120);
          } catch (rowErr) {
            console.error("Row processing error", rowErr);
            failed++;
            errors.push(Object.assign({}, r, { Error: `Processing error: ${rowErr.message || rowErr}` }));
          }
          // update progress
          setStatus(statusEl, `Processed ${i + 1}/${rows.length} — Success: ${success}, Failed: ${failed}`);
        }

        // done: show summary
        setStatus(statusEl, `✅ Import finished. Success: ${success}, Failed: ${failed}`);

        if (errors.length) {
          try {
            // create error report XLSX
            const headerRow = Object.keys(Object.assign({}, errors[0]));
            const ws = XLSX.utils.json_to_sheet(errors, { header: headerRow });
            const wbOut = XLSX.utils.book_new();
            XLSX.utils.book_append_sheet(wbOut, ws, "errors");
            const wbout = XLSX.write(wbOut, { bookType: 'xlsx', type: 'array' });
            const blob = new Blob([wbout], { type: "application/octet-stream" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a"); a.href = url; a.download = "parents_import_errors.xlsx"; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);
            showToast("Error report downloaded");
          } catch (er) { console.error("Failed to export error report", er); }
        } else {
          showToast(`${success} parents added successfully`);
        }

      };
      // prefer binary read but fallback to arrayBuffer
      try { reader.readAsBinaryString(f); } catch (e) { reader.readAsArrayBuffer(f); }
    } catch (err) {
      setStatus(statusEl, "Import failed: " + err.message, true);
    }
  });

  /* ============================
     DYNAMIC XLSX TEMPLATE DOWNLOAD (NEW)
     - Creates an .xlsx with headers and current bus & stop options (for admin reference)
     ============================ */
  getEl("bulkTemplateBtn").addEventListener("click", async () => {
    const statusEl = getEl("bulkStatus");
    setStatus(statusEl, "Preparing template...");
    try {
      // Build rows: add a sample and, for reference, an extra sheet with bus->stops mapping
      const templateRows = [
        { StudentName: "Student A", ParentName: "Parent A", Phone: "9876543210", Class: "5", BusNumber: "", BusStop: "" }
      ];

      // Build buses mapping sheet from live cache
      const buses = Cache.get("buses") || [];
      const mapping = [];
      buses.forEach(b => {
        const stops = Array.isArray(b.stops) ? b.stops : [];
        if (stops.length) {
          stops.forEach(s => mapping.push({ BusDocId: b.id, BusNumber: b.busNumber || "", RouteName: b.routeName || "", StopId: s.id || "", StopName: s.name || "" }));
        } else {
          mapping.push({ BusDocId: b.id, BusNumber: b.busNumber || "", RouteName: b.routeName || "", StopId: "", StopName: "" });
        }
      });

      // Create workbook & sheets
      const wb = XLSX.utils.book_new();
      const wsTemplate = XLSX.utils.json_to_sheet(templateRows);
      XLSX.utils.book_append_sheet(wb, wsTemplate, "Template");
      const wsMapping = XLSX.utils.json_to_sheet(mapping);
      XLSX.utils.book_append_sheet(wb, wsMapping, "Bus_Stop_Reference");

      // Write and trigger download
      const wbout = XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
      const blob = new Blob([wbout], { type: "application/octet-stream" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a"); a.href = url; a.download = "parents_import_template.xlsx"; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);

      setStatus(statusEl, "Template ready (includes Bus_Stop_Reference sheet)");
      showToast("Template downloaded");
    } catch (err) {
      console.error("Template creation failed", err);
      setStatus(statusEl, "Template creation failed: " + err.message, true);
    }
  });

  /* ============================
     Search filtering for parents list
     ============================ */
  getEl("parentSearch").addEventListener("input", () => {
    const q = (getEl("parentSearch").value || "").toLowerCase().trim();
    if (!q) return renderParentsList(parentsCache);
    const filtered = parentsCache.filter(p => (p.studentName || "").toLowerCase().includes(q) || (p.name || "").toLowerCase().includes(q) || (p.phone || "").includes(q));
    renderParentsList(filtered);
  });
}

/* Driver, Buses, Achievements, Circulars pages (unchanged from original file) */

/* Drivers page */
function renderDriverPage(root) {
  root.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:12px">
      <h2 style="margin:0;color:${THEME.text}">Drivers</h2>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
        <div class="app-card">
          <h3 style="margin:0 0 8px 0">Add / Update Driver</h3>
          <form id="driverForm" style="display:flex;flex-direction:column;gap:8px">
            <input id="d_name" class="input-field" placeholder="Driver name" />
            <input id="d_phone" class="input-field" placeholder="Driver phone" />
            <select id="d_bus" class="input-field"><option value=''>-- select bus --</option></select>
            <div style="display:flex;gap:8px">
              <button class="btn btn-primary" type="submit">Create / Update Driver</button>
              <button id="driverResetBtn" type="button" class="btn btn-secondary">Reset</button>
            </div>
            <div id="driverFormStatus" class="small-muted" style="display:none;margin-top:6px"></div>
          </form>
        </div>
        <div class="app-card">
          <h3 style="margin:0 0 8px 0">Search drivers</h3>
          <input id="driverSearch" class="input-field" placeholder="Search by name or phone"/>
          <div id="driversList" class="typeahead-list" style="margin-top:12px"></div>
        </div>
      </div>
    </div>
  `;

  Cache.subscribe("buses", buses => {
    const sel = getEl("d_bus");
    if (!sel) return;
    sel.innerHTML = `<option value=''>-- select bus --</option>`;
    buses.forEach(b => sel.innerHTML += `<option value="${b.id}">${b.busNumber || b.busName || "Unnamed"}</option>`);
  });

  let driversCache = [];
  Cache.subscribe("drivers", data => {
    driversCache = data;
    renderDriversList(driversCache);
  });

  function renderDriversList(arr) {
    const el = getEl("driversList");
    el.innerHTML = arr.map(d => `
      <div style="display:flex;justify-content:space-between;align-items:center;padding:10px;border-radius:8px;border:1px solid #f3f4f6;margin-bottom:8px">
        <div>
          <div style="font-weight:700">${d.name || "—"} <span class="small-muted">(${d.phone || ''})</span></div>
          <div class="small-muted">Bus: ${(Cache.get("buses").find(b => b.id === d.assignedBus) || {}).busNumber || "—"}</div>
        </div>
        <div style="display:flex;flex-direction:column;gap:8px">
          <button class="btn btn-secondary edit-driver" data-id="${d.id}">Edit</button>
          <button class="btn btn-danger delete-driver" data-id="${d.id}">Delete</button>
        </div>
      </div>
    `).join("") || `<div class="small-muted">No drivers</div>`;

    el.querySelectorAll(".edit-driver").forEach(b =>
      b.addEventListener("click", ev => {
        const id = ev.currentTarget.dataset.id;
        const d = driversCache.find(x => x.id === id);
        if (!d) return;
        getEl("d_name").value = d.name || "";
        getEl("d_phone").value = d.phone || "";
        getEl("d_bus").value = d.assignedBus || "";
        getEl("driverForm").dataset.selected = id;
        showToast("Loaded driver for editing", "#f59e0b");
      })
    );

    el.querySelectorAll(".delete-driver").forEach(b =>
      b.addEventListener("click", async ev => {
        const id = ev.currentTarget.dataset.id;
        if (!confirm("Delete driver doc? Auth account remains.")) return;
        await safeExec(async () => {
          await deleteDoc(doc(db, "drivers", id));
        }, "Driver deleted");
      })
    );
  }

  getEl("driverForm").addEventListener("submit", async ev => {
    ev.preventDefault();
    const name = getEl("d_name").value.trim(),
      phone = cleanPhone(getEl("d_phone").value.trim()),
      busId = getEl("d_bus").value,
      statusEl = getEl("driverFormStatus");

    if (!name || !phone || phone.length < 10)
      return setStatus(statusEl, "Invalid details", true);

    const selected = getEl("driverForm").dataset.selected;

    if (selected) {
      // === Update existing driver ===
      await safeExec(async () => {
        await updateDoc(doc(db, "drivers", selected), {
          name,
          phone,
          assignedBus: busId,
          updatedAt: serverTimestamp(),
          role: "driver" // ✅ ensure existing driver keeps role
        });

        // enforce single-driver-per-bus
        const buses = Cache.get("buses");
        const batch = writeBatch(db);
        buses.forEach(b => {
          if (b.driverId === selected && b.id !== busId)
            batch.update(doc(db, "buses", b.id), { driverId: "", driverName: "", driverPhone: "" });
          if (b.id === busId)
            batch.update(doc(db, "buses", b.id), { driverId: selected, driverName: name, driverPhone: phone });
        });
        await batch.commit();
      }, "Driver updated", statusEl);

      getEl("driverForm").reset();
      delete getEl("driverForm").dataset.selected;

    } else {
      // === Create new driver ===
      await safeExec(async () => {
        const email = `${phone}@${SYNTH_DOMAIN}`;
        const pw = `Driver@321`;
        const cred = await createUserWithEmailAndPassword(auth, email, pw);

        await setDoc(doc(db, "drivers", cred.user.uid), {
          uid: cred.user.uid,
          name,
          phone,
          assignedBus: busId,
          createdAt: serverTimestamp(),
          role: "driver" // ✅ added this line
        });

        if (busId)
          await updateDoc(doc(db, "buses", busId), {
            driverId: cred.user.uid,
            driverName: name,
            driverPhone: phone
          });
      }, "Successfully added driver", statusEl);

      getEl("driverForm").reset();
    }
  });

  getEl("driverResetBtn").addEventListener("click", () => {
    getEl("driverForm").reset();
    delete getEl("driverForm").dataset.selected;
  });

  getEl("driverSearch").addEventListener("input", () => {
    const q = (getEl("driverSearch").value || "").toLowerCase().trim();
    if (!q) return renderDriversList(driversCache);
    const filtered = driversCache.filter(d =>
      (d.name || "").toLowerCase().includes(q) || (d.phone || "").includes(q)
    );
    renderDriversList(filtered);
  });
}

/* Buses & Stops page with Leaflet + Add Bus (unchanged) */
function renderBusesPage(root) {
  root.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:12px">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <h2 style="margin:0;color:${THEME.text}">Buses & Routes</h2>
        <input id="busSearch" class="input-field" placeholder="Search bus by number or route" style="max-width:320px"/>
      </div>

      <div class="app-card" style="display:flex;flex-direction:column;gap:12px">
        <div style="display:flex;align-items:center;gap:12px">
          <label style="min-width:120px;font-weight:600;color:#374151">Select Bus</label>
          <select id="map_bus_select" class="input-field" style="min-width:320px"><option value=''>-- select bus --</option></select>
          <div style="margin-left:auto" class="small-muted">Select a bus to show all stops on map (numbered)</div>
        </div>

        <div style="display:flex;gap:16px;align-items:flex-start">
          <div id="mapBig" style="flex:1;height:520px;border-radius:10px;overflow:hidden"></div>
          <div style="width:380px;max-height:520px;overflow:auto;padding:12px">
            <h4 style="margin:0 0 8px 0">Stops</h4>
            <div id="stopsList"></div>
          </div>
        </div>
      </div>

      <div class="app-card" id="addStopCard" style="display:flex;flex-direction:column;gap:10px">
        <h3 style="margin:0 0 6px 0">Add Stop</h3>
        <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">
          <select id="stop_bus_select" class="input-field" style="min-width:220px"><option value=''>-- select bus --</option></select>
          <input id="stop_name" class="input-field" placeholder="Stop name" style="min-width:240px" />
          <input id="stop_lat" class="input-field" placeholder="Latitude" readonly style="width:140px" />
          <input id="stop_lng" class="input-field" placeholder="Longitude" readonly style="width:140px" />
          <input id="stop_position" class="input-field" placeholder="Insert at position (optional)" style="width:160px" />
          <div style="margin-left:auto;display:flex;gap:8px"><button id="addStopBtn" class="btn btn-primary">Add Stop</button><button id="removeStopBtn" class="btn btn-danger">Remove Stop</button></div>
        </div>
        <div id="stopFormStatus" class="small-muted" style="display:none"></div>
        <div class="small-muted">Tip: click map to set lat/lng for a stop.</div>
      </div>

      <div id="busListCard" class="app-card">
        <h3 style="margin:0 0 8px 0">All Buses</h3>
        <div id="busesGrid" style="display:grid;grid-template-columns:repeat(2,1fr);gap:12px"></div>
      </div>

      <!-- Add Bus Section -->
      <div class="app-card" id="addBusCard" style="display:flex;flex-direction:column;gap:10px">
        <h3 style="margin:0 0 6px 0">Add Bus</h3>
        <form id="addBusForm" style="display:flex;flex-direction:column;gap:8px;max-width:860px">
          <div style="display:flex;gap:8px">
            <input id="new_bus_no" class="input-field" placeholder="Bus Number (manual)" style="flex:1"/>
            <input id="new_route_name" class="input-field" placeholder="Route Name" style="flex:1"/>
          </div>
          <div style="display:flex;gap:8px">
            <select id="new_driver" class="input-field" style="flex:1"><option value=''>-- assign driver (optional) --</option></select>
            <input id="new_capacity" class="input-field" placeholder="Capacity (optional)" style="width:160px"/>
            <input id="new_color" class="input-field" placeholder="Color code (optional e.g. #FFD700)" style="width:160px"/>
          </div>
          <div style="display:flex;gap:8px;justify-content:flex-end">
            <button type="submit" class="btn btn-primary">Create Bus</button>
          </div>
          <div id="addBusStatus" class="small-muted" style="display:none"></div>
        </form>
      </div>
    </div>
  `;

  // Initialize Leaflet map safely
  let map = null;
  try {
    map = L.map('mapBig', { zoomControl: true, attributionControl: false }).setView([11.9416, 79.8083], 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }).addTo(map);
    map._traqer_marker_group = L.layerGroup().addTo(map);
  } catch (e) {
    const mb = getEl("mapBig"); if (mb) mb.innerHTML = `<div style="height:100%;display:flex;align-items:center;justify-content:center">Map failed to load</div>`;
  }

  function numberedIcon(text) {
    return L.divIcon({ html: `<div style="background:${THEME.primary};color:white;border-radius:50%;width:34px;height:34px;display:flex;align-items:center;justify-content:center;font-weight:700;border:2px solid white">${text}</div>`, className: '', iconSize: [34, 34], iconAnchor: [17, 34] });
  }

  // Populate selects & grid from cache
  Cache.subscribe("buses", buses => {
    const mapSel = getEl("map_bus_select"), stopSel = getEl("stop_bus_select"), grid = getEl("busesGrid");
    if (!mapSel || !stopSel || !grid) return;
    mapSel.innerHTML = `<option value=''>-- select bus --</option>`;
    stopSel.innerHTML = `<option value=''>-- select bus --</option>`;
    grid.innerHTML = "";
    buses.forEach(b => {
      const label = b.busNumber || b.busName || "Unnamed";
      mapSel.innerHTML += `<option value="${b.id}">${label}</option>`;
      stopSel.innerHTML += `<option value="${b.id}">${label}</option>`;

      const stops = (b.stops || []).slice().sort((a, b2) => (a.order || 0) - (b2.order || 0));
      const card = document.createElement("div"); card.className = "app-card"; card.style.padding = "12px";
      card.innerHTML = `<div style="display:flex;justify-content:space-between;align-items:flex-start">
        <div><div style="font-weight:700">${label} <span class="small-muted">${b.routeName || ""}</span></div><div class="small-muted">Driver: ${b.driverName || "—"}</div><div class="small-muted">Stops: ${stops.length}</div></div>
        <div style="display:flex;flex-direction:column;gap:8px"><button class="btn btn-primary view-stops" data-id="${b.id}">View Stops</button><button class="btn btn-secondary edit-bus" data-id="${b.id}">Edit</button></div>
      </div><div style="margin-top:10px;font-size:13px;color:#374151">${stops.slice(0, 4).map(s => `• ${s.order || '-'} ${s.name || 'Unnamed'}`).join("<br>")}${stops.length > 4 ? ("<div class='small-muted'>+" + (stops.length - 4) + " more</div>") : ""}</div>`;
      grid.appendChild(card);
    });

    document.querySelectorAll(".view-stops").forEach(b => b.addEventListener("click", ev => {
      const id = ev.currentTarget.dataset.id; getEl("map_bus_select").value = id; getEl("map_bus_select").dispatchEvent(new Event("change"));
      getEl("mapBig").scrollIntoView({ behavior: "smooth", block: "center" });
    }));
  });

  // Populate new driver select
  Cache.subscribe("drivers", drivers => {
    const sel = getEl("new_driver"); if (!sel) return;
    sel.innerHTML = `<option value=''>-- assign driver (optional) --</option>`;
    drivers.forEach(d => sel.innerHTML += `<option value="${d.id}">${d.name || d.phone || d.id}</option>`);
  });

  // Bus search filtering
  getEl("busSearch").addEventListener("input", () => {
    const q = (getEl("busSearch").value || "").toLowerCase().trim();
    document.querySelectorAll("#busesGrid .app-card").forEach(card => { card.style.display = card.innerText.toLowerCase().includes(q) ? "" : "none"; });
  });

  // Map click to set lat/lng fields
  if (map) {
    map.on("click", e => {
      const { lat, lng } = e.latlng;
      getEl("stop_lat").value = lat.toFixed(6); getEl("stop_lng").value = lng.toFixed(6);
      map._traqer_marker_group.clearLayers();
      L.marker([lat, lng], { icon: numberedIcon("•") }).addTo(map._traqer_marker_group).bindPopup(`Selected: ${lat.toFixed(5)}, ${lng.toFixed(5)}`).openPopup();
    });
  }

  // Add Stop (transactional)
  getEl("addStopBtn").addEventListener("click", async () => {
    const busId = getEl("stop_bus_select").value, name = (getEl("stop_name").value || "").trim();
    const lat = parseFloat(getEl("stop_lat").value), lng = parseFloat(getEl("stop_lng").value);
    const pos = (getEl("stop_position").value || "").trim(), statusEl = getEl("stopFormStatus");
    if (!busId) return setStatus(statusEl, "Select a bus first", true);
    if (!name) return setStatus(statusEl, "Enter stop name", true);
    if (Number.isNaN(lat) || Number.isNaN(lng)) return setStatus(statusEl, "Pick coordinates on map", true);

    await safeExec(async () => {
      await runTransaction(db, async tx => {
        const busRef = doc(db, "buses", busId);
        const snap = await tx.get(busRef);
        if (!snap.exists()) throw new Error("Bus not found");
        const stops = snap.data().stops || [];
        const insertAt = (pos && !isNaN(parseInt(pos))) ? Math.max(0, parseInt(pos) - 1) : stops.length;
        const newStop = { id: genId("stop"), name, location: { lat, lng }, order: 0 };
        stops.splice(insertAt, 0, newStop);
        stops.forEach((s, i) => s.order = i + 1);
        tx.update(busRef, { stops });
      });
    }, "Successfully added stop", statusEl);

    getEl("stop_name").value = ""; getEl("stop_lat").value = ""; getEl("stop_lng").value = ""; getEl("stop_position").value = "";
    if (getEl("map_bus_select").value === busId) await loadStopsForBus(busId, map);
  });

  // Remove stop (transactional) - prompt for index
  getEl("removeStopBtn").addEventListener("click", async () => {
    const busId = getEl("stop_bus_select").value, statusEl = getEl("stopFormStatus");
    if (!busId) return setStatus(statusEl, "Choose bus first", true);
    try {
      const bs = await getDoc(doc(db, "buses", busId));
      if (!bs.exists()) return setStatus(statusEl, "Bus not found", true);
      const stops = bs.data().stops || [];
      if (!stops.length) return setStatus(statusEl, "No stops to remove", true);
      const list = stops.map(s => `${s.order}. ${s.name || 'Unnamed'} (id:${s.id})`).join("\n");
      const choice = prompt(`Enter stop order number to remove (e.g. 2):\n${list}`);
      if (!choice) return;
      const idx = parseInt(choice) - 1;
      if (isNaN(idx) || idx < 0 || idx >= stops.length) return setStatus(statusEl, "Invalid selection", true);
      await safeExec(async () => {
        await runTransaction(db, async tx => {
          const busRef = doc(db, "buses", busId);
          const snap = await tx.get(busRef);
          const sarr = snap.data().stops || []; sarr.splice(idx, 1); sarr.forEach((s, i) => s.order = i + 1);
          tx.update(busRef, { stops: sarr });
        });
      }, "Stop removed and orders updated", statusEl);
      if (getEl("map_bus_select").value === busId) await loadStopsForBus(busId, map);
    } catch (err) { setStatus(getEl("stopFormStatus"), err.message, true); }
  });

  // When selecting a bus on the main map select -> load stops
  getEl("map_bus_select").addEventListener("change", async (ev) => {
    const id = ev.target.value;
    if (!id) { getEl("stopsList").innerHTML = `<div class="small-muted">Select bus to view stops</div>`; map && map._traqer_marker_group.clearLayers(); return; }
    await loadStopsForBus(id, map);
  });

  // Keep add-stop select synced
  getEl("stop_bus_select").addEventListener("change", () => { });

  // Add Bus submission
  getEl("addBusForm").addEventListener("submit", async ev => {
    ev.preventDefault();
    const busNo = (getEl("new_bus_no").value || "").trim();
    const route = (getEl("new_route_name").value || "").trim();
    const driverId = getEl("new_driver").value || "";
    const capacity = parseInt(getEl("new_capacity").value) || null;
    const color = (getEl("new_color").value || "").trim() || null;
    const statusEl = getEl("addBusStatus");
    if (!busNo) return setStatus(statusEl, "Bus Number required", true);
    await safeExec(async () => {
      // create bus doc with empty stops
      const docRef = await addDoc(collection(db, "buses"), {
        busNumber: busNo,
        routeName: route || "",
        driverId: driverId || "",
        driverName: "",
        driverPhone: "",
        capacity: capacity,
        colorCode: color,
        stops: [],
        createdAt: serverTimestamp()
      });
      // if driver assigned, update driver & bus mapping
      if (driverId) {
        await updateDoc(doc(db, "drivers", driverId), { assignedBus: docRef.id });
        await updateDoc(doc(db, "buses", docRef.id), { driverId: driverId });
      }
      // reset form
      getEl("addBusForm").reset();
    }, "Bus added", statusEl);
  });
}

/* Load stops for bus: show list and numbered markers (unchanged) */
async function loadStopsForBus(busId, mapInstance) {
  const stopsListEl = getEl("stopsList");
  if (!stopsListEl) return;
  stopsListEl.innerHTML = `<div class="small-muted">Loading stops...</div>`;
  try {
    const busSnap = await getDoc(doc(db, "buses", busId));
    if (!busSnap.exists()) { stopsListEl.innerHTML = `<div class="small-muted">Bus not found</div>`; return; }
    const bdata = busSnap.data();
    const stops = (bdata.stops || []).slice().sort((a, b) => (a.order || 0) - (b.order || 0));
    if (!stops.length) { stopsListEl.innerHTML = `<div class="small-muted">No stops</div>`; if (mapInstance && mapInstance._traqer_marker_group) mapInstance._traqer_marker_group.clearLayers(); return; }

    stopsListEl.innerHTML = stops.map(s => `
      <div style="display:flex;justify-content:space-between;align-items:center;padding:8px;border-bottom:1px solid #f3f4f6">
        <div><div style="font-weight:700">${s.order || '?'} . ${s.name || 'Unnamed Stop'}</div><div class="small-muted">Lat: ${Number(s.location?.lat || 0).toFixed(5)} • Lng: ${Number(s.location?.lng || 0).toFixed(5)}</div></div>
        <div style="display:flex;flex-direction:column;gap:8px">
          <button class="btn btn-secondary edit-stop" data-id="${s.id}" data-bus="${busId}" style="min-width:80px">Edit</button>
          <button class="btn btn-danger delete-stop" data-id="${s.id}" data-bus="${busId}" style="min-width:80px">Delete</button>
        </div>
      </div>`).join("");

    if (mapInstance) {
      if (mapInstance._traqer_marker_group) mapInstance._traqer_marker_group.clearLayers();
      else mapInstance._traqer_marker_group = L.layerGroup().addTo(mapInstance);
      const mg = mapInstance._traqer_marker_group; const bounds = [];
      stops.forEach(s => {
        if (s.location && Number(s.location.lat) && Number(s.location.lng)) {
          const lat = Number(s.location.lat), lng = Number(s.location.lng);
          const icon = L.divIcon({ html: `<div style="background:${THEME.primary};color:white;border-radius:50%;width:34px;height:34px;display:flex;align-items:center;justify-content:center;font-weight:700;border:2px solid white">${s.order}</div>`, className: '', iconSize: [34, 34], iconAnchor: [17, 34] });
          const m = L.marker([lat, lng], { icon }).addTo(mg);
          m.bindPopup(`${s.order}. ${s.name || 'Unnamed Stop'}`);
          bounds.push([lat, lng]);
        }
      });
      if (bounds.length) try { mapInstance.fitBounds(bounds, { padding: [40, 40] }); } catch (e) { }
    }

    // attach edit/delete handlers
    stopsListEl.querySelectorAll(".edit-stop").forEach(btn => btn.addEventListener("click", async ev => {
      const stopId = ev.currentTarget.dataset.id, bus = ev.currentTarget.dataset.bus;
      const parentDiv = ev.currentTarget.closest("div");
      const nameEl = parentDiv.querySelector("div > div");
      const currentName = nameEl ? nameEl.textContent.replace(/^\d+\.\s*/, "").trim() : "";
      // inline edit: replace left with input
      const input = document.createElement("input"); input.className = "input-field"; input.value = currentName;
      parentDiv.querySelector("div").replaceWith(input);
      const control = document.createElement("div"); control.style.display = "flex"; control.style.flexDirection = "column"; control.style.gap = "8px";
      const save = document.createElement("button"); save.className = "btn btn-primary"; save.textContent = "Save";
      const cancel = document.createElement("button"); cancel.className = "btn btn-secondary"; cancel.textContent = "Cancel";
      control.appendChild(save); control.appendChild(cancel);
      ev.currentTarget.parentElement.replaceWith(control);
      save.addEventListener("click", async () => {
        const newName = input.value.trim(); if (!newName) return alert("Name required");
        await safeExec(async () => { await editStopName(bus, stopId, newName); }, "Stop updated");
        await loadStopsForBus(bus, mapInstance);
      });
      cancel.addEventListener("click", () => loadStopsForBus(bus, mapInstance));
    }));

    stopsListEl.querySelectorAll(".delete-stop").forEach(btn => btn.addEventListener("click", async ev => {
      const stopId = ev.currentTarget.dataset.id, bus = ev.currentTarget.dataset.bus;
      if (!confirm("Delete this stop?")) return;
      await safeExec(async () => { await deleteStop(bus, stopId); }, "Stop deleted");
      await loadStopsForBus(bus, mapInstance);
    }));

  } catch (err) {
    stopsListEl.innerHTML = `<div class="small-muted">Failed to load stops: ${err.message}</div>`;
    if (mapInstance && mapInstance._traqer_marker_group) mapInstance._traqer_marker_group.clearLayers();
  }
}

/* editStopName & deleteStop (unchanged) */
async function editStopName(busId, stopId, newName) {
  await runTransaction(db, async tx => {
    const busRef = doc(db, "buses", busId);
    const snap = await tx.get(busRef);
    if (!snap.exists()) throw new Error("Bus missing");
    const stops = snap.data().stops || [];
    const idx = stops.findIndex(s => s.id === stopId); if (idx === -1) throw new Error("Stop not found");
    stops[idx].name = newName; tx.update(busRef, { stops });
  });
}
async function deleteStop(busId, stopId) {
  await runTransaction(db, async tx => {
    const busRef = doc(db, "buses", busId);
    const snap = await tx.get(busRef);
    if (!snap.exists()) throw new Error("Bus missing");
    const stops = snap.data().stops || [];
    const idx = stops.findIndex(s => s.id === stopId); if (idx === -1) throw new Error("Stop not found");
    stops.splice(idx, 1); stops.forEach((s, i) => s.order = i + 1); tx.update(busRef, { stops });
  });
}

/* Achievements (unchanged) */
function renderAchievementsPage(root) {
  root.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:12px">
      <h2 style="margin:0;color:${THEME.text}">Achievements</h2>
      <div class="app-card" style="max-width:800px">
        <form id="achForm" style="display:flex;flex-direction:column;gap:8px">
          <input id="achTitle" class="input-field" placeholder="Title" />
          <textarea id="achDesc" class="input-field" placeholder="Description" rows="4"></textarea>
          <div style="display:flex;gap:8px"><button class="btn btn-primary" type="submit">Publish</button><button id="achReset" class="btn btn-secondary" type="button">Reset</button></div>
          <div id="achStatus" class="small-muted" style="display:none;margin-top:6px"></div>
        </form>
      </div>
      <div id="achList" class="app-card"></div>
    </div>
  `;
  getEl("achForm").addEventListener("submit", async ev => {
    ev.preventDefault();
    const title = getEl("achTitle").value.trim(), desc = getEl("achDesc").value.trim(), st = getEl("achStatus");
    if (!title || !desc) return setStatus(st, "Title & description required", true);
    await safeExec(async () => { await addDoc(collection(db, "achievements"), { title, description: desc, createdAt: serverTimestamp() }); getEl("achForm").reset(); }, "Achievement published", st);
  });
  getEl("achReset").addEventListener("click", () => getEl("achForm").reset());
  onSnapshot(collection(db, "achievements"), snap => {
    const out = snap.docs.map(d => {
      const data = d.data();
      return `<div style="display:flex;gap:12px;align-items:flex-start;padding:10px;border-bottom:1px solid #f3f4f6">
        <div style="flex:1"><div style="font-weight:700">${data.title}</div><div class="small-muted">${data.description}</div><div class="small-muted" style="margin-top:6px">${data.createdAt ? new Date(data.createdAt.seconds * 1000).toLocaleString() : ""}</div></div>
        <div><button class="btn btn-danger delete-ach" data-id="${d.id}">Delete</button></div>
      </div>`;
    }).join("");
    getEl("achList").innerHTML = out || `<div class="small-muted">No achievements yet</div>`;
    document.querySelectorAll(".delete-ach").forEach(b => b.addEventListener("click", async ev => { if (!confirm("Delete achievement?")) return; await safeExec(async () => { await deleteDoc(doc(db, "achievements", ev.currentTarget.dataset.id)); }, "Achievement deleted"); }));
  });
}

/* Circulars page (unchanged) */
function renderCircularsPage(root) {
  root.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:12px">
      <h2 style="margin:0;color:${THEME.text}">Circulars</h2>
      <div class="app-card" style="max-width:720px">
        <form id="circForm" style="display:flex;flex-direction:column;gap:8px">
          <input id="circTitle" class="input-field" placeholder="Title" />
          <textarea id="circBody" class="input-field" placeholder="Message" rows="4"></textarea>
          <button class="btn btn-primary" type="submit">Publish</button>
        </form>
      </div>
      <div id="circList" class="app-card"></div>
    </div>
  `;
  getEl("circForm").addEventListener("submit", async ev => {
    ev.preventDefault(); const t = getEl("circTitle").value.trim(), b = getEl("circBody").value.trim();
    if (!t || !b) return alert("Provide title & body");
    await safeExec(async () => { await addDoc(collection(db, "circulars"), { title: t, body: b, createdAt: serverTimestamp() }); getEl("circForm").reset(); }, "Circular published");
  });
  onSnapshot(collection(db, "circulars"), snap => {
    const out = snap.docs.map(d => { const data = d.data(); return `<div style="padding:10px;border-bottom:1px solid #f3f4f6"><div style="font-weight:700">${data.title}</div><div class="small-muted">${data.body}</div></div>`; }).join("");
    getEl("circList").innerHTML = out || `<div class="small-muted">No circulars</div>`;
  });
}

/* Router & init (unchanged) */
async function renderPage(page) {
  const root = getEl("pageContent");
  if (!root) return;
  try {
    switch (page) {
      case "parents": renderParentPage(root); break;
      case "drivers": renderDriverPage(root); break;
      case "buses": renderBusesPage(root); break;
      case "achievements": renderAchievementsPage(root); break;
      case "circulars": renderCircularsPage(root); break;
      default: renderOverview(root);
    }
  } catch (e) {
    console.error("Render page error", e);
    root.innerHTML = `<div class="app-card"><h3>Failed to load page</h3><div class="small-muted">${e.message}</div></div>`;
  }
}

/* Expose a helper to allow driver app or other to send location updates */
async function sendDriverLocationUpdate(busId, lat, lng, extra = {}) {
  if (!busId) throw new Error("Missing busId");
  const payload = Object.assign({ lat, lng, timestamp: Date.now() }, extra);
  await rtdbSet(rtdbRef(rtdb, `${LIVE_LOCATIONS_PATH}/${busId}`), payload);
}

/* Auth guard: show login or dashboard (unchanged) */
onAuthStateChanged(auth, async (user) => {
  try {
    if (user) {
      await Cache.init();
      renderDashboardShell();
      renderPage("overview");
    } else {
      renderLogin();
    }
  } catch (e) {
    console.error("Init error:", e);
    const app = getEl("app");
    if (app) app.innerHTML = `<div style="padding:40px;text-align:center"><h3>App failed to load</h3><div class="small-muted">${e.message}</div></div>`;
  }
});

// Export helpers for debugging from console
window.__traqer_admin_helpers = { Cache, sendDriverLocationUpdate, safeExec, loadStopsForBus, editStopName, deleteStop };

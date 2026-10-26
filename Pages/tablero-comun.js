/* =================================================================
   Tablero de decisiones: funciones comunes de Dashboard.html y
   Tablero.html (formatos, periodos, pedidos a la API, graficos).
   ================================================================= */
var TB = (function () {
  var MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
  var DIAS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];

  var fmtPeso = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 });
  var fmtNum = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
  var fmtDec = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

  function n(v) { var x = Number(v); return isFinite(x) ? x : 0; }

  function dinero(v) { return v === null || v === undefined ? "—" : fmtPeso.format(Math.round(n(v))).replace(/ /g, " "); }
  // $ 1,2 M / $ 850 mil: para titulares cortos
  function dineroCorto(v) {
    var x = n(v), a = Math.abs(x);
    if (a >= 1e6) return "$ " + fmtDec.format(x / 1e6) + " M";
    if (a >= 1e4) return "$ " + fmtNum.format(Math.round(x / 1e3)) + " mil";
    return dinero(x);
  }
  function num(v) { return v === null || v === undefined ? "—" : fmtNum.format(n(v)); }
  function dec(v) { return v === null || v === undefined ? "—" : fmtDec.format(n(v)); }
  function pct(v) { return v === null || v === undefined ? "—" : fmtDec.format(n(v)) + "%"; }

  // Variacion contra el periodo anterior: texto y clase de color
  function variacion(actual, anterior, menosEsMejor) {
    actual = n(actual); anterior = n(anterior);
    if (!anterior) return { txt: actual ? "sin datos del período anterior" : "", clase: "neutro", valor: null };
    var v = (actual - anterior) / Math.abs(anterior) * 100;
    var sube = v >= 0;
    var bueno = menosEsMejor ? !sube : sube;
    if (Math.abs(v) < 0.5) return { txt: "igual que el período anterior", clase: "neutro", valor: 0 };
    return { txt: (sube ? "▲ " : "▼ ") + fmtDec.format(Math.abs(v)) + "% vs. período anterior", clase: bueno ? "bien" : "mal", valor: v };
  }

  function iso(d) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  function aFecha(s) {
    if (!s) return null;
    if (s instanceof Date) return s;
    var m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(s);
  }

  // Periodos rapidos
  function rango(clave) {
    var hoy = new Date(); hoy.setHours(0, 0, 0, 0);
    var y = hoy.getFullYear(), m = hoy.getMonth();
    switch (clave) {
      case "mes": return { desde: iso(new Date(y, m, 1)), hasta: iso(hoy) };
      case "mesAnterior": return { desde: iso(new Date(y, m - 1, 1)), hasta: iso(new Date(y, m, 0)) };
      case "3m": return { desde: iso(new Date(y, m - 2, 1)), hasta: iso(hoy) };
      case "6m": return { desde: iso(new Date(y, m - 5, 1)), hasta: iso(hoy) };
      case "12m": return { desde: iso(new Date(y, m - 11, 1)), hasta: iso(hoy) };
      case "anio": return { desde: iso(new Date(y, 0, 1)), hasta: iso(hoy) };
      case "anioAnterior": return { desde: iso(new Date(y - 1, 0, 1)), hasta: iso(new Date(y - 1, 11, 31)) };
    }
    return { desde: iso(new Date(y, m, 1)), hasta: iso(hoy) };
  }

  function mesCorto(s) { var d = aFecha(s); return d ? MESES[d.getMonth()].slice(0, 3) + " " + String(d.getFullYear()).slice(2) : ""; }
  function mesLargo(s) { var d = aFecha(s); return d ? MESES[d.getMonth()] + " " + d.getFullYear() : ""; }
  function fecha(s) { var d = aFecha(s); return d ? String(d.getDate()).padStart(2, "0") + "/" + String(d.getMonth() + 1).padStart(2, "0") + "/" + String(d.getFullYear()).slice(2) : "—"; }
  function hace(s) {
    var d = aFecha(s); if (!d) return "nunca";
    var dias = Math.floor((Date.now() - d.getTime()) / 86400000);
    if (dias <= 0) return "hoy";
    if (dias === 1) return "ayer";
    if (dias < 60) return "hace " + dias + " días";
    if (dias < 730) return "hace " + Math.round(dias / 30) + " meses";
    return "hace " + Math.round(dias / 365) + " años";
  }

  function esc(s) {
    if (s === null || s === undefined) return "";
    return String(s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; });
  }

  function get(ruta, params) {
    var q = params ? "?" + Object.keys(params).filter(function (k) { return params[k] != null; })
      .map(function (k) { return k + "=" + encodeURIComponent(params[k]); }).join("&") : "";
    return fetchAuth(API_BASE + ruta + q).then(function (r) {
      if (!r.ok) return Promise.reject(r.status === 403 ? "Tu usuario no tiene permiso para ver esto." : "No se pudo cargar (" + r.status + ").");
      return r.json();
    });
  }

  // Graficos con el estilo del sistema
  var COLOR = { navy: "#001f3f", navySoft: "#4a6a8f", rojo: "#d92020", verde: "#1f8a4c", ambar: "#c98a00", gris: "#9aa6b4", grilla: "#e8ecf1", texto: "#5b6878" };
  function baseChart() {
    if (!window.Chart) return;
    Chart.defaults.font.family = "'Segoe UI', Arial, sans-serif";
    Chart.defaults.color = COLOR.texto;
    Chart.defaults.plugins.legend.labels.boxWidth = 12;
    Chart.defaults.plugins.tooltip.backgroundColor = "#0b1e33";
    Chart.defaults.maintainAspectRatio = false;
  }
  var graficos = {};
  function grafico(id, config) {
    if (graficos[id]) graficos[id].destroy();
    var el = document.getElementById(id);
    if (!el || !window.Chart) return null;
    graficos[id] = new Chart(el, config);
    return graficos[id];
  }
  function ejePesos() {
    return { grid: { color: COLOR.grilla }, border: { display: false }, ticks: { callback: function (v) { return dineroCorto(v); } } };
  }

  function guardar(k, v) { try { localStorage.setItem("tablero." + k, v); } catch (e) { } }
  function leer(k) { try { return localStorage.getItem("tablero." + k); } catch (e) { return null; } }

  return {
    MESES: MESES, DIAS: DIAS, COLOR: COLOR, n: n,
    dinero: dinero, dineroCorto: dineroCorto, num: num, dec: dec, pct: pct, variacion: variacion,
    iso: iso, aFecha: aFecha, rango: rango, mesCorto: mesCorto, mesLargo: mesLargo, fecha: fecha, hace: hace,
    esc: esc, get: get, baseChart: baseChart, grafico: grafico, ejePesos: ejePesos, guardar: guardar, leer: leer
  };
})();

/* =================================================================
   vincular.js — Vincular y agrupar equivalentes (script 65)

   Una sola ventana para dos cosas distintas:

   MISMO ARTICULO: el articulo del otro proveedor ES este repuesto
   (misma marca, mismo codigo). Comparten stock y precio.

   EQUIVALENTE: la misma pieza de OTRA marca. Cada uno mantiene su
   stock; quedan agrupados para ofrecer uno cuando no hay el otro.

   Los resultados vienen ordenados por parecido y con la marca bien
   visible, porque es lo que decide entre una y otra cosa.

   Uso: abrirVinculacion(idRepuesto, { titulo, intro, alTerminar })
   Necesita: config.js (API_BASE), auth.js (fetchAuth), precio.js, SweetAlert2.
   ================================================================= */
(function () {

  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function plata(n) {
    return typeof formatearMoneda === "function" ? formatearMoneda(n) : "$ " + n;
  }

  function leerErr(r) {
    return r.text().then(function (t) {
      try { var j = JSON.parse(t); return j.Message || j.message || t; } catch (e) { return t || "Error"; }
    });
  }

  function css() {
    if (document.getElementById("vx-css")) return;
    var st = document.createElement("style");
    st.id = "vx-css";
    st.textContent =
      ".vx{text-align:left}" +
      ".vx-rep{border:1px solid #d6e4f5;background:#f5f9fe;border-radius:10px;padding:10px 12px;margin-bottom:10px}" +
      ".vx-rep .d{font-weight:700;font-size:.95rem}" +
      ".vx-rep .m{font-size:.8rem;color:#555;margin-top:3px}" +
      ".vx-marca{display:inline-block;font-weight:800;font-size:.78rem;letter-spacing:.4px;" +
        "padding:2px 8px;border-radius:6px;text-transform:uppercase;vertical-align:middle}" +
      ".vx-m-MISMA{background:#d1f0dc;color:#0f5132}" +
      ".vx-m-OTRA{background:#ffe5cc;color:#8a4500}" +
      ".vx-m-SIN_DATO{background:#eceff1;color:#555}" +
      ".vx-sec{font-weight:700;font-size:.85rem;margin:12px 0 4px}" +
      ".vx-sec small{font-weight:400;color:#6c757d}" +
      ".vx-fila{display:flex;gap:10px;align-items:center;border:1px solid #dee2e6;border-radius:9px;" +
        "padding:8px 10px;margin-bottom:6px;background:#fff}" +
      ".vx-fila.sel-mismo{border-color:#1266d1;background:#eef5ff}" +
      ".vx-fila.sel-equiv{border-color:#d9822b;background:#fff7ee}" +
      ".vx-info{flex:1;min-width:0}" +
      ".vx-l1{font-size:.83rem;font-weight:600}" +
      ".vx-l2{font-size:.75rem;color:#6c757d;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
      ".vx-l3{font-size:.72rem;color:#8a4500;margin-top:2px}" +
      ".vx-cod{background:#cfe2ff;color:#084298;border-radius:7px;font-size:.65rem;padding:1px 6px;margin-left:4px}" +
      ".vx-precio{text-align:right;white-space:nowrap;font-size:.8rem}" +
      ".vx-precio .t{font-size:.62rem;color:#6c757d;text-transform:uppercase}" +
      ".vx-ops{display:flex;flex-direction:column;gap:4px}" +
      ".vx-op{border:1px solid #ced4da;background:#fff;border-radius:6px;font-size:.72rem;padding:3px 8px;white-space:nowrap;cursor:pointer}" +
      ".vx-op[disabled]{opacity:.35;cursor:not-allowed}" +
      ".vx-op.on[data-op=mismo]{background:#1266d1;border-color:#1266d1;color:#fff}" +
      ".vx-op.on[data-op=equiv]{background:#d9822b;border-color:#d9822b;color:#fff}" +
      ".vx-eq{display:flex;align-items:center;gap:8px;border:1px dashed #d9822b;border-radius:8px;padding:6px 9px;margin-bottom:5px;font-size:.8rem}" +
      ".vx-eq .x{margin-left:auto;border:0;background:none;color:#c0392b;font-size:1rem;cursor:pointer}";
    document.head.appendChild(st);
  }

  function badgeMarca(marca, rel) {
    var txt = marca && String(marca).trim() ? marca : "Sin marca";
    return '<span class="vx-marca vx-m-' + (rel || "SIN_DATO") + '">' + esc(txt) + '</span>';
  }

  window.abrirVinculacion = function (idRepuesto, opc) {
    opc = opc || {};
    css();

    var estado = {};          // Id candidato -> 'mismo' | 'equiv'
    var datos = {};           // Id candidato -> fila
    var repuesto = null;
    var primera = true;
    var timer = null;

    function cargar(texto) {
      var res = document.getElementById("vxRes");
      if (!res) return;
      res.innerHTML = '<div class="text-center p-3"><span class="spinner-border spinner-border-sm"></span></div>';

      var url = API_BASE + "Repuesto/" + idRepuesto + "/Vinculacion" +
                (texto ? "?texto=" + encodeURIComponent(texto) : "");
      fetchAuth(url)
        .then(function (r) {
          if (!r.ok) return leerErr(r).then(function (m) { throw new Error(m); });
          return r.json();
        })
        .then(function (d) {
          repuesto = (d.Repuesto && d.Repuesto[0]) || null;
          pintarRepuesto();
          if (primera && repuesto) {
            document.getElementById("vxTexto").value = repuesto.TextoUsado || "";
            primera = false;
          }
          pintarCandidatos(d.Candidatos || []);
          pintarEquivalentes(d.Equivalentes || []);
        })
        .catch(function (e) {
          res.innerHTML = '<div class="form-text text-danger">' + esc(e.message || "No se pudo buscar.") + '</div>';
        });
    }

    function pintarRepuesto() {
      var c = document.getElementById("vxRep");
      if (!c || !repuesto) return;
      c.innerHTML =
        '<div class="d">' + esc(repuesto.Descripcion) + '</div>' +
        '<div class="m">' + badgeMarca(repuesto.MarcaFabricante, "MISMA") +
          ' · código <strong>' + esc(repuesto.Codigo || "-") + '</strong>' +
          (repuesto.CodigoFabricante ? ' · fab ' + esc(repuesto.CodigoFabricante) : '') +
          ' · stock ' + esc(repuesto.Stock) + '</div>';
    }

    function fila(c) {
      datos[c.Id] = c;
      var sel = estado[c.Id] || "";
      var noMismo = !!c.IdRepuestoEnlazado || c.ProveedorYaVinculado == 1;
      var dif = c.DiferenciaPorc;
      var color = dif < 0 ? "#157347" : (dif > 0 ? "#c0392b" : "#6c757d");

      var nota = "";
      if (c.IdRepuestoEnlazado)
        nota = 'Ya es tu repuesto ' + esc(c.CodigoEnlazado || "") + ': solo puede ir como equivalente.';
      else if (c.ProveedorYaVinculado == 1)
        nota = 'Este proveedor ya tiene otro artículo vinculado a este repuesto.';
      else if (c.Marca === "OTRA")
        nota = 'Otra marca: va como equivalente.';

      return '<div class="vx-fila' + (sel ? ' sel-' + sel : '') + '" data-id="' + c.Id + '">' +
        '<div class="vx-info">' +
          '<div class="vx-l1">' + badgeMarca(c.MarcaTexto, c.Marca) + ' ' +
            esc(c.Proveedor) + ' · ' + esc(c.CodigoProveedor) +
            (c.Articulo ? ' · fab ' + esc(c.Articulo) : '') +
            (c.MismoCodigo == 1 ? '<span class="vx-cod">mismo código de fábrica</span>' : '') +
          '</div>' +
          '<div class="vx-l2" title="' + esc(c.Descripcion) + '">' + esc(c.Descripcion) + '</div>' +
          (nota ? '<div class="vx-l3">' + nota + '</div>' : '') +
        '</div>' +
        '<div class="vx-precio"><div class="t">costo</div><strong>' + plata(c.PrecioCompra) + '</strong>' +
          (dif !== null && dif !== undefined
            ? '<div style="color:' + color + ';font-size:.7rem;">' + (dif > 0 ? '+' : '') + dif + '% vs el tuyo</div>'
            : '') +
        '</div>' +
        '<div class="vx-ops">' +
          '<button type="button" class="vx-op' + (sel === "mismo" ? " on" : "") + '" data-op="mismo"' +
            (noMismo ? ' disabled' : '') + '>Mismo artículo</button>' +
          '<button type="button" class="vx-op' + (sel === "equiv" ? " on" : "") + '" data-op="equiv">Equivalente</button>' +
        '</div>' +
      '</div>';
    }

    function pintarCandidatos(lista) {
      var res = document.getElementById("vxRes");
      if (!res) return;
      if (lista.length === 0) {
        res.innerHTML = '<div class="form-text">Sin resultados. Probá con menos palabras o con el código.</div>';
        return;
      }

      // Pre-marcar solo lo seguro, la primera vez que aparece
      lista.forEach(function (c) {
        if (c.Sugerido === "MISMO" && estado[c.Id] === undefined) estado[c.Id] = "mismo";
      });

      var marca = repuesto && repuesto.MarcaFabricante ? esc(repuesto.MarcaFabricante) : "";
      var grupos = [
        { k: "MISMA", t: "Misma marca" + (marca ? " (" + marca + ")" : ""), s: "el mismo artículo en otra lista" },
        { k: "SIN_DATO", t: "Marca sin dato", s: "fijate la marca en la descripción" },
        { k: "OTRA", t: "Otras marcas", s: "la misma pieza de otra marca va como equivalente" }
      ];

      var html = "";
      grupos.forEach(function (g) {
        var del = lista.filter(function (c) { return c.Marca === g.k; });
        if (!del.length) return;
        html += '<div class="vx-sec">' + g.t + ' <small>· ' + g.s + '</small></div>';
        del.forEach(function (c) { html += fila(c); });
      });
      res.innerHTML = html;
    }

    function pintarEquivalentes(lista) {
      var c = document.getElementById("vxEq");
      if (!c) return;
      if (!lista.length) { c.innerHTML = ""; return; }

      var html = '<div class="vx-sec">Ya agrupados como equivalentes <small>· ' + lista.length + '</small></div>';
      lista.forEach(function (e) {
        var cat = e.Tipo === "CATALOGO";
        html += '<div class="vx-eq">' + badgeMarca(e.Marca, "OTRA") +
          '<span style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' +
            esc(e.Descripcion) + '</span>' +
          '<span style="white-space:nowrap;color:#6c757d;font-size:.75rem;">' +
            (cat ? 'stock ' + e.Stock + ' · ' + plata(e.Precio)
                 : esc(e.Proveedor || "") + ' · costo ' + plata(e.Precio)) + '</span>' +
          '<button type="button" class="x" title="Sacar del grupo" ' +
            (cat ? 'data-qrep="' + e.IdRepuesto + '"' : 'data-qpr="' + e.IdProveedorRepuesto + '"') +
            '>&times;</button>' +
        '</div>';
      });
      c.innerHTML = html;
    }

    function quitar(body) {
      fetchAuth(API_BASE + "Equivalencias/Quitar", { method: "POST", body: JSON.stringify(body) })
        .then(function (r) {
          if (!r.ok) return leerErr(r).then(function (m) { throw new Error(m); });
          cargar(document.getElementById("vxTexto").value.trim());
        })
        .catch(function (e) { Swal.showValidationMessage(e.message || "No se pudo sacar."); });
    }

    Swal.fire({
      title: opc.titulo || "Vincular y equivalentes",
      html:
        '<div class="vx">' +
          (opc.intro ? '<div class="mb-2">' + opc.intro + '</div>' : '') +
          '<div id="vxRep" class="vx-rep"><span class="spinner-border spinner-border-sm"></span></div>' +
          '<div class="form-text mb-1"><strong>Mismo artículo</strong>: misma marca y código, comparten stock. ' +
            '<strong>Equivalente</strong>: la misma pieza de otra marca, cada uno con su stock. Los importes son costo.</div>' +
          '<input type="text" id="vxTexto" class="form-control mb-1" placeholder="Ej: kit distribucion suran, KTB341...">' +
          '<div id="vxRes" style="max-height:340px;overflow-y:auto;"></div>' +
          '<div id="vxEq"></div>' +
        '</div>',
      width: 760,
      showCancelButton: true,
      confirmButtonText: "Guardar",
      cancelButtonText: opc.cancelar || "Cancelar",
      confirmButtonColor: "#1266d1",
      didOpen: function () {
        var campo = document.getElementById("vxTexto");
        campo.addEventListener("input", function () {
          clearTimeout(timer);
          timer = setTimeout(function () {
            var v = campo.value.trim();
            if (v.length === 0 || v.length >= 3) cargar(v);
          }, 350);
        });

        var cont = document.getElementById("vxRes");
        cont.addEventListener("click", function (ev) {
          var b = ev.target.closest(".vx-op");
          if (!b || b.disabled) return;
          var f = b.closest(".vx-fila");
          var id = parseInt(f.getAttribute("data-id"), 10);
          var op = b.getAttribute("data-op");
          estado[id] = estado[id] === op ? "" : op;
          f.classList.remove("sel-mismo", "sel-equiv");
          if (estado[id]) f.classList.add("sel-" + estado[id]);
          f.querySelectorAll(".vx-op").forEach(function (x) {
            x.classList.toggle("on", x.getAttribute("data-op") === estado[id]);
          });
        });

        document.getElementById("vxEq").addEventListener("click", function (ev) {
          var b = ev.target.closest(".x");
          if (!b) return;
          if (b.getAttribute("data-qrep")) quitar({ IdRepuesto: parseInt(b.getAttribute("data-qrep"), 10) });
          else quitar({ IdProveedorRepuesto: parseInt(b.getAttribute("data-qpr"), 10) });
        });

        cargar("");
      },
      preConfirm: function () {
        var mismo = [], equiv = [];
        Object.keys(estado).forEach(function (k) {
          if (estado[k] === "mismo") mismo.push(parseInt(k, 10));
          if (estado[k] === "equiv") equiv.push(parseInt(k, 10));
        });
        if (!mismo.length && !equiv.length) {
          Swal.showValidationMessage("Marcá al menos uno, o cancelá.");
          return false;
        }
        return { mismo: mismo, equiv: equiv };
      }
    }).then(function (res) {
      if (!res.isConfirmed || !res.value) {
        if (opc.alCancelar) opc.alCancelar();
        return;
      }
      revisarMarcas(res.value);
    });

    /* Mismo artículo con otra marca: casi siempre es un error, y
       vincular une el stock. Se avisa antes de guardar. */
    function revisarMarcas(sel) {
      var otras = sel.mismo.filter(function (id) { return datos[id] && datos[id].Marca === "OTRA"; });
      if (!otras.length) return guardar(sel);

      var lista = otras.map(function (id) {
        var c = datos[id];
        return '<li>' + badgeMarca(c.MarcaTexto, "OTRA") + ' ' + esc(c.Proveedor) + ' · ' + esc(c.CodigoProveedor) + '</li>';
      }).join("");

      Swal.fire({
        icon: "warning",
        title: "Hay otras marcas como mismo artículo",
        html: '<div style="text-align:left;">' +
          '<ul style="padding-left:18px;">' + lista + '</ul>' +
          '<div class="form-text">Si los vinculás como el mismo artículo van a compartir el stock con ' +
          badgeMarca(repuesto && repuesto.MarcaFabricante, "MISMA") +
          ': vendés uno y se descuenta el otro. Lo normal es agruparlos como equivalentes.</div></div>',
        showDenyButton: true,
        showCancelButton: true,
        confirmButtonText: "Pasarlos a equivalentes",
        denyButtonText: "Vincular igual",
        cancelButtonText: "Volver",
        confirmButtonColor: "#d9822b"
      }).then(function (r) {
        if (r.isConfirmed) {
          sel.mismo = sel.mismo.filter(function (id) { return otras.indexOf(id) === -1; });
          sel.equiv = sel.equiv.concat(otras);
          guardar(sel);
        } else if (r.isDenied) {
          guardar(sel);
        } else {
          window.abrirVinculacion(idRepuesto, opc);
        }
      });
    }

    /* De a uno y en orden: dos equivalencias en paralelo podrian
       crear dos grupos en vez de uno. */
    function guardar(sel) {
      var tareas = [];
      sel.mismo.forEach(function (id) { tareas.push({ tipo: "mismo", id: id }); });
      sel.equiv.forEach(function (id) { tareas.push({ tipo: "equiv", id: id }); });

      var okM = 0, okE = 0, errores = [];
      Swal.fire({ title: "Guardando...", allowOutsideClick: false, didOpen: function () { Swal.showLoading(); } });

      tareas.reduce(function (p, t) {
        return p.then(function () {
          var req = t.tipo === "mismo"
            ? fetchAuth(API_BASE + "ProveedorRepuesto/" + t.id + "/Enlazar",
                { method: "PUT", body: JSON.stringify({ IdRepuesto: idRepuesto }) })
            : fetchAuth(API_BASE + "Repuesto/" + idRepuesto + "/Equivalentes",
                { method: "POST", body: JSON.stringify({ IdProveedorRepuesto: t.id }) });
          return req.then(function (r) {
            if (r.ok) { if (t.tipo === "mismo") okM++; else okE++; return; }
            return leerErr(r).then(function (m) {
              var c = datos[t.id] || {};
              errores.push(esc((c.Proveedor || "") + " " + (c.CodigoProveedor || "")) + ": " + esc(m));
            });
          }).catch(function () { errores.push("Error de conexión"); });
        });
      }, Promise.resolve()).then(function () {
        var partes = [];
        if (okM) partes.push(okM + " vinculado" + (okM > 1 ? "s" : "") + " como mismo artículo");
        if (okE) partes.push(okE + " equivalente" + (okE > 1 ? "s" : ""));
        Swal.fire({
          icon: errores.length ? (partes.length ? "warning" : "error") : "success",
          title: partes.length ? partes.join(" · ") : "No se guardó nada",
          html: errores.length ? '<div style="text-align:left;font-size:.85rem;">' + errores.join("<br>") + '</div>' : ""
        }).then(function () {
          if (opc.alTerminar) opc.alTerminar();
        });
      });
    }
  };
})();

/* =================================================================
   Equivalencias.cargar() / Equivalencias.conStock(idRepuesto)
   Otras marcas del mismo grupo con stock disponible (script 66).
   Se carga una vez por pantalla; son pocos repuestos.
   ================================================================= */
window.Equivalencias = {
  porId: {},
  porGrupo: {},
  cargar: function () {
    var self = this;
    return fetchAuth(API_BASE + "Equivalencias/Mapa")
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (lista) {
        self.porId = {}; self.porGrupo = {};
        (lista || []).forEach(function (e) {
          self.porId[e.IdRepuesto] = e.IdGrupo;
          (self.porGrupo[e.IdGrupo] = self.porGrupo[e.IdGrupo] || []).push(e);
        });
      })
      .catch(function () { self.porId = {}; self.porGrupo = {}; });
  },
  conStock: function (idRepuesto) {
    var g = this.porId[idRepuesto];
    if (!g) return [];
    return (this.porGrupo[g] || []).filter(function (e) {
      return e.IdRepuesto !== idRepuesto && e.StockDisponible > 0;
    });
  },
  // Chips "otra marca con stock". accion = nombre de funcion global que recibe el Id
  chips: function (idRepuesto, accion) {
    var otros = this.conStock(idRepuesto);
    if (!otros.length) return "";
    var esc = function (s) {
      return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    };
    var html = '<div style="margin-top:4px;font-size:.74rem;color:#8a4500;display:flex;flex-wrap:wrap;gap:4px;align-items:center;">' +
      '<span><i class="bi bi-arrow-left-right"></i> Otra marca con stock:</span>';
    otros.slice(0, 4).forEach(function (e) {
      html += '<button type="button" onclick="event.stopPropagation();' + accion + '(' + e.IdRepuesto + ')" ' +
        'title="' + esc(e.Descripcion) + '" ' +
        'style="border:1px solid #f0c9a0;background:#fff7ee;color:#8a4500;border-radius:12px;padding:1px 8px;font-size:.72rem;cursor:pointer;">' +
        '<strong>' + esc(e.Marca || e.Codigo || "Sin marca") + '</strong> · ' + e.StockDisponible +
        (typeof formatearMoneda === "function" ? ' · ' + formatearMoneda(e.PrecioDeVenta) : '') +
        '</button>';
    });
    return html + '</div>';
  }
};

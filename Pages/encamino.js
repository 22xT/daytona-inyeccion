/* =================================================================
   encamino.js — "este repuesto ya está pedido" (28/10)

   Prueba C3 de Sofi: se podía pedir dos veces lo mismo sin enterarse.
   Carga una vez lo que está pedido y sin recibir (api/Compras/EnCamino,
   script 91) y lo muestra donde se pide: Buscador, Carrito y Pedido manual.
     EnCamino.cargar()        -> promesa; después de pedir, volver a llamar
     EnCamino.chip(id)        -> etiqueta corta para la fila ("2 pedidos")
     EnCamino.aviso(id)       -> recuadro para el diálogo de pedir
     EnCamino.refrescar()     -> actualiza las etiquetas [data-encamino]
   ================================================================= */
(function (global) {
  'use strict';
  var porRep = {};

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function dia(f) {
    var d = new Date(f);
    return isNaN(d) ? "" : d.toLocaleDateString("es-AR", { weekday: "short", day: "numeric", month: "numeric" });
  }
  function total(id) {
    return (porRep[id] || []).reduce(function (s, x) { return s + (Number(x.Cantidad) || 0); }, 0);
  }
  function detalle(x) {
    return (Number(x.Cantidad) || 0) + " en el pedido N° " + x.IdPedido + " de " + esc(x.Proveedor) +
      (x.EnArmado ? " (en armado, todavía no se envió)" : (x.LlegadaEstimada ? " (enviado, llega aprox. " + dia(x.LlegadaEstimada) + ")" : " (enviado)"));
  }

  var EnCamino = {
    cargar: function () {
      if (typeof fetchAuth !== "function") return Promise.resolve();
      return fetchAuth(API_BASE + "Compras/EnCamino")
        .then(function (r) { return r.ok ? r.json() : []; })
        .then(function (lista) {
          porRep = {};
          (lista || []).forEach(function (x) { (porRep[x.IdRepuesto] = porRep[x.IdRepuesto] || []).push(x); });
          EnCamino.refrescar();
        })
        .catch(function () { porRep = {}; });
    },
    de: function (id) { return porRep[id] || []; },
    chip: function (id) {
      var l = porRep[id] || [];
      var t = '<span class="en-pedido" data-encamino="' + id + '"' + (l.length ? '' : ' hidden') + ' title="' +
        esc(l.map(function (x) { return detalle(x).replace(/&[a-z#0-9]+;/g, ""); }).join(" · ")) + '"' +
        ' style="font-size:.72rem;font-weight:700;color:#7a5600;background:#fff3d1;border-radius:5px;padding:1px 7px;white-space:nowrap;">';
      if (!l.length) return t + '</span>';
      var armado = l.some(function (x) { return x.EnArmado; });
      return t + '<i class="bi bi-box-seam"></i> ' + total(id) + ' ya pedido' + (total(id) === 1 ? '' : 's') +
        (armado ? ' (en armado)' : '') + '</span>';
    },
    aviso: function (id) {
      var l = porRep[id] || [];
      if (!l.length) return "";
      return '<div class="alert alert-warning py-2 px-3 mb-2" style="font-size:0.85rem;text-align:left;">' +
        '<i class="bi bi-box-seam"></i> <strong>Ya está pedido:</strong> ' +
        l.map(detalle).join("; ") + '. Lo que pidas ahora se suma.</div>';
    },
    refrescar: function () {
      if (!global.document) return;
      document.querySelectorAll("[data-encamino]").forEach(function (el) {
        var id = parseInt(el.getAttribute("data-encamino"), 10);
        var tmp = document.createElement("div");
        tmp.innerHTML = EnCamino.chip(id);
        el.replaceWith(tmp.firstChild);
      });
    }
  };
  global.EnCamino = EnCamino;
})(window);

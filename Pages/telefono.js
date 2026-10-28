/* =================================================================
   telefono.js — telefono argentino para WhatsApp (28/10)

   Pruebas E1/E4 de Sofi: se guardaban telefonos de 19 digitos o todo
   ceros. Ahora se acepta como lo escriba el vendedor:
       351 7585566 · 0351 15 758-5566 · +54 9 351 7585566 · 3517585566
   y se guarda siempre igual: codigo de area (sin 0) + espacio + numero
   (sin 15), por ejemplo "351 7585566". Son 10 digitos: lo que necesita
   WhatsApp (wa.me/549 + esos 10 digitos).
   ================================================================= */
(function (global) {
  'use strict';

  // Codigos de area de 2 y 3 digitos; el resto son de 4 (ej. 3543)
  var AREA2 = ["11"];
  var AREA3 = ["220", "221", "223", "230", "236", "237", "249", "260", "261", "263", "264", "266",
               "280", "291", "294", "297", "298", "299", "336", "341", "342", "343", "345", "348",
               "351", "353", "358", "362", "364", "370", "376", "379", "380", "381", "383", "385",
               "387", "388"];

  function largoArea(d) {
    if (AREA2.indexOf(d.substr(0, 2)) !== -1) return 2;
    if (AREA3.indexOf(d.substr(0, 3)) !== -1) return 3;
    return 4;
  }

  // Devuelve los 10 digitos, o null si no es un numero valido
  function normalizar(txt) {
    var d = String(txt == null ? "" : txt).replace(/\D/g, "");
    if (d.indexOf("549") === 0 && d.length === 13) d = d.slice(3);
    else if (d.indexOf("54") === 0 && d.length === 12) d = d.slice(2);
    if (d.charAt(0) === "0") d = d.slice(1);
    // 0351 15 7585566 -> se saca el 15 que va despues del codigo de area
    if (d.length === 12) {
      for (var a = 2; a <= 4; a++) {
        if (d.substr(a, 2) === "15") { d = d.slice(0, a) + d.slice(a + 2); break; }
      }
    }
    if (d.length !== 10 || d.charAt(0) === "0" || /^(\d)\1+$/.test(d)) return null;
    return d;
  }

  // "3517585566" -> "351 7585566"
  function formatear(txt) {
    var d = normalizar(txt);
    if (!d) return String(txt == null ? "" : txt).trim();
    var a = largoArea(d);
    return d.slice(0, a) + " " + d.slice(a);
  }

  // Mensaje de error, o "" si esta bien. obligatorio: si puede quedar vacio
  function validar(txt, obligatorio) {
    var t = String(txt == null ? "" : txt).trim();
    if (!t) return obligatorio ? "Falta el teléfono (con código de área, ej. 351 7585566)." : "";
    if (normalizar(t)) return "";
    var d = t.replace(/\D/g, "");
    if (/^(\d)\1+$/.test(d)) return "El teléfono no parece real.";
    if (d.length < 10) return "Al teléfono le faltan números: va el código de área y el número, ej. 351 7585566.";
    return "El teléfono tiene números de más: va el código de área y el número, ej. 351 7585566.";
  }

  // Numero para wa.me: 549 + los 10 digitos
  function whatsapp(txt) {
    var d = normalizar(txt);
    if (d) return "549" + d;
    var n = String(txt == null ? "" : txt).replace(/\D/g, "");
    return n.indexOf("54") === 0 ? n : "549" + n.replace(/^0+/, "");
  }

  // Al salir del campo, si es valido queda escrito con el formato
  function activar(input) {
    if (!input) return;
    if (!input.placeholder) input.placeholder = "351 7585566";
    input.setAttribute("inputmode", "tel");
    input.addEventListener("blur", function () {
      if (normalizar(input.value)) input.value = formatear(input.value);
    });
  }

  global.Telefono = { normalizar: normalizar, formatear: formatear, validar: validar, whatsapp: whatsapp, activar: activar };
})(window);

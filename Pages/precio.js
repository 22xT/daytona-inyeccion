// ============================================================
// precio.js — Manejo unificado de precios en formato argentino
// ============================================================

const PRECIO_MAXIMO = 10000000; // tope por defecto: 10 millones

// Formatea mientras el usuario escribe: "58000" -> "58.000"
// max (opcional): tope distinto al de por defecto. Ej: PedidoNuevo usa 50.000.000
function formatearPrecioInput(valor, max) {
  const tope = (typeof max === "number" && max > 0) ? max : PRECIO_MAXIMO;
  valor = String(valor).replace(/[^\d,]/g, "");
  const partes = valor.split(",");
  let entero = partes[0].replace(/\./g, "");
  let decimal = partes.length > 1 ? "," + partes[1].slice(0, 2) : "";
  if (entero !== "" && parseInt(entero, 10) > tope) {
    entero = String(tope);
    decimal = "";
  }
  entero = entero.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return entero + decimal;
}

// Convierte el texto formateado al número real: "58.000,50" -> 58000.50
function precioANumero(texto) {
  if (!texto) return NaN;
  const limpio = String(texto).replace(/\./g, "").replace(",", ".");
  return parseFloat(limpio);
}

// Convierte un número de la base al texto formateado: 58000.5 -> "58.000,50"
function numeroAPrecio(num) {
  if (num === null || num === undefined || isNaN(num)) return "";
  return Number(num).toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Igual que numeroAPrecio pero con el símbolo: 58000.5 -> "$58.000,50"
// Para mostrar montos en tablas, totales y mensajes.
function formatearMoneda(num) {
  return "$" + numeroAPrecio(num);
}

// Aplica el formato a un input concreto, conservando la posición del cursor
function formatearEnVivo(el, max) {
  const posFin = el.value.length - el.selectionStart;
  el.value = formatearPrecioInput(el.value, max);
  el.selectionStart = el.selectionEnd = Math.max(0, el.value.length - posFin);
}

// Engancha el formateo a un input fijo, por id
function activarInputPrecio(idInput, max) {
  const el = document.getElementById(idInput);
  if (!el) return;
  el.addEventListener("input", function () { formatearEnVivo(el, max); });
}

// Engancha el formateo por CLASE, con delegación en document.
// Sirve para inputs que se crean o re-dibujan dinámicamente (filas de una tabla).
// Llamar UNA sola vez por clase (si se llama dos veces, formatea dos veces).
function activarInputsPrecioPorClase(clase, max) {
  document.addEventListener("input", function (e) {
    const el = e.target;
    if (!el || !el.classList || !el.classList.contains(clase)) return;
    formatearEnVivo(el, max);
  });
}

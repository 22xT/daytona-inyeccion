// ===============================================
// CONFIGURACIÓN DE ENDPOINTS
// ===============================================
const apiUrl = "http://localhost:52954/api/Repuesto";
const apiMarca = "http://localhost:52954/api/Marca";
const apiModelo = "http://localhost:52954/api/Modelo";
const apiRubro = "http://localhost:52954/api/Rubro";
const apiProveedor = "http://localhost:52954/api/Proveedor";

// ===============================================
// CARGA DE COMBOS (RUBRO, MARCA, MODELO, PROVEEDOR)
// ===============================================
async function cargarListas() {
  const marcaSel = document.getElementById("marca");
  const modeloSel = document.getElementById("modelo");
  const rubroSel = document.getElementById("rubro");
  const proveedorSel = document.getElementById("proveedor");

  // 🔹 Cargar marcas
  const marcas = await fetch(apiMarca).then(r => r.json());
  marcaSel.innerHTML =
    '<option value="">Seleccione marca</option>' +
    marcas.map(m => `<option value="${m.Id}">${m.Nombre}</option>`).join("");

  // 🔹 Cargar rubros
  const rubros = await fetch(apiRubro).then(r => r.json());
  rubroSel.innerHTML =
    '<option value="">Seleccione rubro</option>' +
    rubros.map(r => `<option value="${r.Id}">${r.Nombre}</option>`).join("");

  // 🔹 Cargar proveedores
  const proveedores = await fetch(apiProveedor).then(r => r.json());
  proveedorSel.innerHTML =
    '<option value="">Seleccione proveedor</option>' +
    proveedores.map(p => `<option value="${p.Id}">${p.RazonSocial}</option>`).join("");

  // ===============================================
  // 🔹 Evento: al cambiar marca, cargar modelos
  // ===============================================
  marcaSel.addEventListener("change", async () => {
    const idMarca = marcaSel.value;
    modeloSel.innerHTML = '<option value="">Seleccione modelo</option>';

    if (!idMarca) return;

    try {
      // 🚀 Pedimos los modelos (la API devuelve XML)
      const response = await fetch(apiModelo + "/" + idMarca);
      const xmlText = await response.text();

      // 🧠 Extraemos Id y Nombre desde el XML
      const modelos = Array.from(
        xmlText.matchAll(/<Table>[\s\S]*?<Id>(\d+)<\/Id>[\s\S]*?<Nombre>(.*?)<\/Nombre>/g)
      ).map(m => ({ Id: m[1], Nombre: m[2] }));

      // 🧩 Cargamos las opciones en el combo
      modelos.forEach(mo => {
        modeloSel.innerHTML += `<option value="${mo.Id}">${mo.Nombre}</option>`;
      });

    } catch (error) {
      console.error("Error al cargar modelos:", error);
      alert("❌ No se pudieron cargar los modelos desde la API.");
    }
  });
}

// ===============================================
// GUARDAR REPUESTO NUEVO (manual o API)
// ===============================================
async function guardarRepuesto() {
  const descripcion = document.getElementById("descripcion").value;
  const precio = parseFloat(document.getElementById("precio").value);
  const idModelo = parseInt(document.getElementById("modelo").value);
  const idRubro = parseInt(document.getElementById("rubro").value);
  const idProveedor = parseInt(document.getElementById("proveedor").value);

  if (!descripcion || !precio || !idModelo || !idRubro || !idProveedor) {
    alert("⚠️ Debe completar todos los campos.");
    return;
  }

  const body = {
    Descripcion: descripcion,
    PrecioDeVenta: precio,
    IdModelo: idModelo,
    IdRubro: idRubro,
    IdProveedor: idProveedor
  };

  const res = await fetch(apiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });

  if (res.ok) {
    alert("✅ Repuesto guardado correctamente");
    limpiarCampos();
  } else {
    alert("⚠️ Error al guardar el repuesto");
  }
}

// ===============================================
// GUARDAR EN PEDIDO LOCAL (carrito temporal)
// ===============================================
function agregarAlPedidoLocal() {
  const descripcion = document.getElementById("descripcion").value.trim();
  const rubro = document.getElementById("rubro").selectedOptions[0]?.text;
  const marca = document.getElementById("marca").selectedOptions[0]?.text;
  const modelo = document.getElementById("modelo").selectedOptions[0]?.text;
  const proveedor = document.getElementById("proveedor").selectedOptions[0]?.text;
  const cantidad = parseInt(document.getElementById("cantidad").value);
  const precio = parseFloat(document.getElementById("precio").value);

  if (!descripcion || !rubro || !marca || !modelo || !proveedor || !cantidad || !precio) {
    alert("⚠️ Complete todos los campos antes de agregar al pedido.");
    return;
  }

  const nuevo = { descripcion, rubro, marca, modelo, proveedor, cantidad, precio };
  const pedido = JSON.parse(localStorage.getItem("pedido")) || [];
  pedido.push(nuevo);
  localStorage.setItem("pedido", JSON.stringify(pedido));

  alert("✅ Repuesto agregado al pedido actual.");
  limpiarCampos();
}

// ===============================================
// LIMPIAR CAMPOS
// ===============================================
function limpiarCampos() {
  document.getElementById("descripcion").value = "";
  document.getElementById("rubro").value = "";
  document.getElementById("marca").value = "";
  document.getElementById("modelo").value = "";
  document.getElementById("proveedor").value = "";
  document.getElementById("precio").value = "";
  document.getElementById("cantidad").value = "";
}

// ===============================================
// EVENTOS DE INICIO
// ===============================================
window.onload = () => {
  cargarListas();

  const btnGuardar = document.getElementById("btnGuardar");
  const btnAgregar = document.getElementById("btnAgregar");

  if (btnGuardar) btnGuardar.addEventListener("click", guardarRepuesto);
  if (btnAgregar) btnAgregar.addEventListener("click", agregarAlPedidoLocal);
};
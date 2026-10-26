using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class VentaController : ApiController
    {
        // Topes, alineados con el front (precio.js) y con la validacion de repuestos
        private const decimal PRECIO_MAXIMO = 10000000m;
        private const int CANTIDAD_MAXIMA = 9999;
        // Venta.Total es DECIMAL(12,2): tope real 9.999.999.999,99
        private const decimal TOTAL_MAXIMO = 999999999m;

        // GET: api/Venta  (todos los roles autenticados menos Analista y Sistema)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get()
        {
            Venta oVenta = new Venta();
            return oVenta.ListarTodos();
        }

        // GET: api/Venta/5  (mismo criterio)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(int id)
        {
            Venta oVenta = new Venta();
            oVenta.Id = id;
            return oVenta.ListarPorId();
        }

        // GET: api/Venta/5/Detalle  (renglones de una venta)
        // Ruta explicita: SP_Venta_GetId devuelve solo la cabecera,
        // el detalle sale de SP_DetalleVenta_GetByVenta.
        [HttpGet]
        [Route("api/Venta/{id:int}/Detalle")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Detalle(int id)
        {
            DetalleVenta oDetalle = new DetalleVenta();
            oDetalle.IdVenta = id;
            return oDetalle.ListarPorVenta();
        }

        // GET: api/Venta/AnuladasRecientes  (popup de aviso al administrador)
        // Necesita ruta explicita: con el ruteo por defecto,
        // "AnuladasRecientes" no bindea contra Get(int id) y da 404.
        [HttpGet]
        [Route("api/Venta/AnuladasRecientes")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public DataTable AnuladasRecientes()
        {
            Venta oVenta = new Venta();
            return oVenta.ListarAnuladasRecientes();
        }

        // POST: api/Venta  (los que pueden vender)
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Post([FromBody] Venta venta)
        {
            // La validacion va ANTES de tocar el objeto: si venta es null,
            // asignarle IdUsuario tira NullReference y devuelve un 500 feo.
            string error = ValidarVenta(venta);
            if (error != "")
                return BadRequest(error);

            // El usuario sale del token, nunca del body: si viniera del cliente,
            // cualquiera podria registrar una venta a nombre de otro vendedor.
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0)
                return BadRequest("No se pudo identificar al usuario de la sesion. Volve a iniciar sesion.");

            venta.IdUsuario = idUsuario;

            // El rol tambien sale del token: decide si puede autorizar pasar
            // el limite de credito (script 82). Lo que venga en el body se pisa.
            var identidad = User.Identity as ClaimsIdentity;
            var claimRol = identidad == null ? null : identidad.FindFirst(ClaimTypes.Role);
            venta.RolUsuario = claimRol == null ? null : claimRol.Value;

            /* ---------- Idempotencia ----------
               Si viene token, se reserva antes de registrar. Un doble clic
               o un reenvio con el mismo token devuelven la venta que ya
               existe en vez de crear otra. Sin token se registra igual:
               los clientes viejos siguen funcionando. */
            bool conToken = venta.TokenOperacion.HasValue && venta.TokenOperacion.Value != Guid.Empty;

            if (conToken)
            {
                int idExistente;
                string estado;
                try { estado = venta.ReservarOperacion(out idExistente); }
                catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo iniciar la operacion.")); }

                if (estado == "EN_CURSO")
                    return Conflict();   // 409: la misma venta se esta registrando ahora

                if (estado == "EXISTE")
                {
                    // Ya se registro con este token: se devuelve la misma
                    Venta existente = new Venta();
                    existente.Id = idExistente;
                    DataTable dt = existente.ListarPorId();
                    decimal totalExistente = dt.Rows.Count > 0 ? Convert.ToDecimal(dt.Rows[0]["Total"]) : 0;
                    return Ok(new
                    {
                        IdVenta       = idExistente,
                        Total         = totalExistente,
                        Descuento     = 0m,
                        Entrega       = 0m,
                        SaldoGenerado = 0m,
                        Duplicada     = true
                    });
                }
            }

            // Validacion de pagos: montos positivos y suma no mayor al total
            // (el total exacto lo valida el SP, que es quien lo calcula)
            if (venta.Pagos != null)
            {
                foreach (VentaPagoItem p in venta.Pagos)
                {
                    if (p.IdMedioPago <= 0) return BadRequest("Cada pago debe indicar el medio.");
                    if (p.Monto <= 0) return BadRequest("Cada pago debe tener un importe mayor a cero.");
                }
            }

            try
            {
                venta.Guardar();
                if (conToken) venta.CompletarOperacion();
                // Se devuelve el saldo generado: en una venta a cuenta
                // corriente es lo que el cliente quedo debiendo, y el
                // vendedor tiene que verlo al confirmar.
                return Ok(new
                {
                    IdVenta       = venta.Id,
                    Total         = venta.Total,
                    Descuento     = venta.Descuento,
                    Entrega       = venta.Entrega,
                    SaldoGenerado = venta.SaldoGenerado,
                    Comision      = venta.Comision
                });
            }
            catch (SqlException ex)
            {
                // Fallo la venta: se libera el token para permitir reintentar
                if (conToken) { try { venta.LiberarOperacion(); } catch { /* best effort */ } }
                return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la venta."));
            }
        }

        // PUT: api/Venta/5/Anular  (los que pueden anular)
        [HttpPut]
        [Route("api/Venta/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Anular(int id)
        {
            if (id <= 0)
                return BadRequest("El identificador de la venta no es valido.");

            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0)
                return BadRequest("No se pudo identificar al usuario de la sesion.");

            Venta oVenta = new Venta();
            oVenta.Id = id;

            try
            {
                // Anular corrige un error del dia; despues, la devolucion es una nota de credito
                new NotaCliente().ValidarAnulacionVenta(id);
                oVenta.Anular(idUsuario);
            }
            catch (SqlException ex)
            {
                return BadRequest(TraducirErrorSql(ex, "No se pudo anular la venta."));
            }

            return Ok();
        }

        /* ============================================================
           VALIDACION
           OJO: el stock NO se valida aca a proposito. Va dentro de
           SP_Venta_I, en la misma transaccion que descuenta. Si se
           chequeara aca, entre el chequeo y el INSERT otro vendedor
           podria llevarse la ultima unidad y la venta entraria igual.
           ============================================================ */
        private string ValidarVenta(Venta venta)
        {
            if (venta == null)
                return "No se recibieron datos de la venta.";

            if (venta.IdCliente <= 0)
                return "Debe indicarse el cliente de la venta.";

            if (venta.Detalle == null || venta.Detalle.Count == 0)
                return "La venta debe tener al menos un repuesto.";

            if (venta.Detalle.Count > 200)
                return "La venta tiene demasiados renglones.";

            // El cliente tiene que existir y estar activo.
            // Los clientes internos (Consumidor Final, Mecanico Mostrador)
            // entran por aca como cualquier otro.
            Cliente oCliente = new Cliente();
            oCliente.Id = venta.IdCliente;
            DataTable dtCliente = oCliente.ListarPorId();

            if (dtCliente == null || dtCliente.Rows.Count == 0)
                return "El cliente seleccionado no existe.";

            bool clienteActivo = Convert.ToBoolean(dtCliente.Rows[0]["Activo"]);
            if (!clienteActivo)
                return "El cliente seleccionado esta dado de baja. Reactivalo o elegi otro.";

            // Renglones
            List<int> vistos = new List<int>();
            decimal total = 0;

            foreach (DetalleVenta d in venta.Detalle)
            {
                if (d == null)
                    return "Hay un renglon vacio en el detalle de la venta.";

                if (d.IdRepuesto <= 0)
                    return "Hay un renglon sin repuesto seleccionado.";

                if (d.Cantidad <= 0)
                    return "La cantidad de cada repuesto debe ser mayor a cero.";

                if (d.Cantidad > CANTIDAD_MAXIMA)
                    return "La cantidad de un repuesto no puede superar " + CANTIDAD_MAXIMA + " unidades.";

                if (d.PrecioUnitario < 0)
                    return "El precio de un repuesto no puede ser negativo.";

                if (d.PrecioUnitario > PRECIO_MAXIMO)
                    return "El precio de un repuesto no puede superar los $10.000.000.";

                // Un mismo repuesto dos veces descontaria stock dos veces
                // y dejaria la venta con renglones duplicados.
                if (vistos.Contains(d.IdRepuesto))
                    return "Hay un repuesto repetido en el detalle. Sumá la cantidad en un solo renglon.";

                vistos.Add(d.IdRepuesto);

                // El repuesto tiene que existir y no estar discontinuado
                Repuesto oRepuesto = new Repuesto();
                oRepuesto.Id = d.IdRepuesto;
                DataTable dtRep = oRepuesto.ListarPorId();

                if (dtRep == null || dtRep.Rows.Count == 0)
                    return "Uno de los repuestos de la venta no existe.";

                bool repActivo = Convert.ToBoolean(dtRep.Rows[0]["Activo"]);
                if (!repActivo)
                {
                    string desc = Convert.ToString(dtRep.Rows[0]["Descripcion"]);
                    return "El repuesto \"" + desc + "\" esta discontinuado y no se puede vender.";
                }

                total += d.Cantidad * d.PrecioUnitario;
            }

            /* ---------- Descuento y forma de pago ---------- */

            if (venta.PorcentajeDescuento < 0 || venta.PorcentajeDescuento > 100)
                return "El descuento debe estar entre 0 y 100.";

            if (!string.IsNullOrEmpty(venta.FormaPago)
                && venta.FormaPago != "Contado" && venta.FormaPago != "CuentaCorriente")
                return "La forma de pago debe ser Contado o CuentaCorriente.";

            if (venta.Entrega.HasValue && venta.Entrega.Value < 0)
                return "La entrega no puede ser negativa.";

            /* La entrega NO se compara contra el total aca: el total con
               descuento lo calcula el procedimiento almacenado, y duplicar
               ese calculo abriria la puerta a que los dos den distinto.
               El SP la valida contra el total real. */

            if (!string.IsNullOrEmpty(venta.NombreOcasional) && venta.NombreOcasional.Length > 80)
                return "El nombre no puede superar los 80 caracteres.";

            if (!string.IsNullOrEmpty(venta.TelefonoOcasional) && venta.TelefonoOcasional.Length > 30)
                return "El telefono no puede superar los 30 caracteres.";

            if (!string.IsNullOrEmpty(venta.TipoCliente)
                && venta.TipoCliente != "Publico" && venta.TipoCliente != "Mecanico")
                return "El tipo de cliente debe ser Publico o Mecanico.";

            if (total <= 0)
                return "El total de la venta debe ser mayor a cero.";

            // Sin este tope, 200 renglones al maximo desbordarian la columna
            // y el error saldria como excepcion de SQL en vez de mensaje claro.
            if (total > TOTAL_MAXIMO)
                return "El total de la venta es demasiado alto.";

            return "";
        }

        // Los RAISERROR del SP traen mensajes pensados para el usuario
        // (numero >= 50000). El resto son errores tecnicos: no se muestran crudos.
        private string TraducirErrorSql(SqlException ex, string mensajeGenerico)
        {
            if (ex.Number >= 50000)
                return ex.Message;

            if (ex.Number == 547)
                return mensajeGenerico + " Algun dato referenciado no existe.";

            return mensajeGenerico + " Intentalo de nuevo o avisá a sistemas.";
        }

        private int ObtenerIdUsuarioActual()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;

            var claim = identity.FindFirst(ClaimTypes.NameIdentifier)
                     ?? identity.FindFirst("sub")
                     ?? identity.FindFirst("Sub");

            int id;
            if (claim != null && int.TryParse(claim.Value, out id))
                return id;
            return 0;
        }
    }
}

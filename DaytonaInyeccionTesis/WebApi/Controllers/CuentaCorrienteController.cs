using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class CuentaCorrienteController : ApiController
    {
        // GET: api/CuentaCorriente?soloConSaldo=true&texto=perez
        // Quien me debe y cuanto. Ordenado por saldo descendente.
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(bool soloConSaldo = true, string texto = null)
        {
            CuentaCorriente oCC = new CuentaCorriente();
            return oCC.ListarTodos(soloConSaldo, texto);
        }

        // GET: api/CuentaCorriente/5
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(int id)
        {
            CuentaCorriente oCC = new CuentaCorriente();
            oCC.IdCliente = id;
            return oCC.ObtenerSaldo();
        }

        // GET: api/CuentaCorriente/5/Movimientos?desde=2026-01-01&hasta=2026-12-31
        [HttpGet]
        [Route("api/CuentaCorriente/{id:int}/Movimientos")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Movimientos(int id, string desde = null, string hasta = null)
        {
            DateTime fd, fh;
            DateTime? fechaDesde = DateTime.TryParse(desde, out fd) ? (DateTime?)fd : null;
            DateTime? fechaHasta = DateTime.TryParse(hasta, out fh) ? (DateTime?)fh : null;

            CuentaCorriente oCC = new CuentaCorriente();
            oCC.IdCliente = id;
            return oCC.ListarMovimientos(fechaDesde, fechaHasta);
        }

        // POST: api/CuentaCorriente/5/Pago
        // El cobro reduce el saldo y registra el ingreso en caja.
        [HttpPost]
        [Route("api/CuentaCorriente/{id:int}/Pago")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult RegistrarPago(int id, [FromBody] CuentaCorriente datos)
        {
            if (id <= 0)
                return BadRequest("El identificador del cliente no es valido.");

            if (datos == null)
                return BadRequest("No se recibieron datos del pago.");

            if (datos.Monto <= 0)
                return BadRequest("El importe del pago debe ser mayor a cero.");

            if (datos.Monto > 99999999)
                return BadRequest("El importe del pago es demasiado alto.");

            if (!string.IsNullOrEmpty(datos.Observaciones) && datos.Observaciones.Length > 300)
                return BadRequest("Las observaciones no pueden superar los 300 caracteres.");

            // El usuario sale del token: si viniera del body, cualquiera
            // podria registrar un cobro a nombre de otro.
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0)
                return BadRequest("No se pudo identificar al usuario de la sesion.");

            datos.IdCliente = id;
            datos.IdUsuario = idUsuario;

            try
            {
                DataTable saldo = datos.RegistrarPago();
                return Ok(saldo);
            }
            catch (SqlException ex)
            {
                return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el pago."));
            }
        }

        // POST: api/CuentaCorriente/5/Ajuste
        // Correccion manual. Monto positivo suma deuda, negativo la reduce.
        // No mueve dinero, por eso no toca la caja.
        [HttpPost]
        [Route("api/CuentaCorriente/{id:int}/Ajuste")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult RegistrarAjuste(int id, [FromBody] CuentaCorriente datos)
        {
            if (id <= 0)
                return BadRequest("El identificador del cliente no es valido.");

            if (datos == null)
                return BadRequest("No se recibieron datos del ajuste.");

            if (datos.Monto == 0)
                return BadRequest("El importe del ajuste no puede ser cero.");

            if (Math.Abs(datos.Monto) > 99999999)
                return BadRequest("El importe del ajuste es demasiado alto.");

            // Un ajuste sin explicacion es indefendible ante un reclamo
            if (string.IsNullOrWhiteSpace(datos.Concepto))
                return BadRequest("El ajuste necesita un concepto que lo explique.");

            if (datos.Concepto.Length > 120)
                return BadRequest("El concepto no puede superar los 120 caracteres.");

            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0)
                return BadRequest("No se pudo identificar al usuario de la sesion.");

            datos.IdCliente = id;
            datos.IdUsuario = idUsuario;

            try
            {
                datos.RegistrarAjuste();
                return Ok();
            }
            catch (SqlException ex)
            {
                return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el ajuste."));
            }
        }

        // Los RAISERROR del SP traen mensajes escritos para el usuario.
        // El resto son errores tecnicos y no se muestran crudos.
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

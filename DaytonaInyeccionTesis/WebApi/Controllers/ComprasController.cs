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
    public class ComprasController : ApiController
    {
        public class MotivoDto { public string Motivo { get; set; } }
        public class AjusteDto { public decimal Monto { get; set; } public string Motivo { get; set; } }

        /* ================= RECEPCION ================= */

        // GET api/Compras/Pedido/5/Recepcion — cabecera, renglones con pendiente, recepciones anteriores
        [HttpGet, Route("api/Compras/Pedido/{id:int}/Recepcion")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public IHttpActionResult ParaRecepcion(int id)
        {
            DataSet ds = new Compras().ParaRecepcion(id);
            if (ds.Tables.Count < 3 || ds.Tables[0].Rows.Count == 0) return NotFound();
            return Ok(new { Pedido = ds.Tables[0], Renglones = ds.Tables[1], Recepciones = ds.Tables[2] });
        }

        // GET api/Compras/ResumenRecepcion — para marcar los parciales en el listado
        [HttpGet, Route("api/Compras/ResumenRecepcion")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable ResumenRecepcion()
        {
            return new Compras().ResumenRecepcion();
        }

        [HttpPost, Route("api/Compras/Pedido/{id:int}/Recibir")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Recibir(int id, [FromBody] Recepcion r)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (r == null || r.Lineas == null || r.Lineas.Count == 0) return BadRequest("Indicá qué llegó.");
            if (r.TotalComprobante <= 0) return BadRequest("Indicá el total del comprobante del proveedor.");

            try
            {
                DataTable dt = new Compras().Recibir(id, r, idUsuario);
                return Ok(new { IdRecepcion = dt.Rows[0]["IdRecepcion"], IdEstadoPedido = dt.Rows[0]["IdEstadoPedido"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la recepción.")); }
        }

        [HttpPost, Route("api/Compras/Recepcion/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult AnularRecepcion(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().AnularRecepcion(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular la recepción.")); }
        }

        [HttpPost, Route("api/Compras/Pedido/{id:int}/CerrarFaltantes")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult CerrarFaltantes(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().CerrarFaltantes(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudieron cerrar los faltantes.")); }
        }

        /* ================= CUENTA CORRIENTE ================= */

        [HttpGet, Route("api/Compras/CuentasProveedor")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Saldos()
        {
            return new Compras().SaldosProveedores();
        }

        [HttpGet, Route("api/Compras/CuentasProveedor/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable Movimientos(int id)
        {
            return new Compras().MovimientosProveedor(id);
        }

        // Saldo inicial o correccion con motivo
        [HttpPost, Route("api/Compras/CuentasProveedor/{id:int}/Ajuste")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Ajuste(int id, [FromBody] AjusteDto a)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (a == null || a.Monto == 0) return BadRequest("Indicá el importe del ajuste.");
            try { new Compras().AjusteProveedor(id, a.Monto, a.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el ajuste.")); }
        }

        /* ================= PAGOS ================= */

        [HttpPost, Route("api/Compras/Pagos")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Pagar([FromBody] PagoProveedorDto p)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (p == null || p.IdProveedor <= 0 || p.IdCuentaFinanciera <= 0) return BadRequest("Faltan el proveedor o la cuenta.");
            if (p.Importe <= 0) return BadRequest("El importe debe ser mayor a cero.");
            try
            {
                DataTable dt = new Compras().Pagar(p, idUsuario);
                return Ok(new { IdPago = dt.Rows[0]["IdPago"], SaldoNuevo = dt.Rows[0]["SaldoNuevo"] });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar el pago.")); }
        }

        [HttpPost, Route("api/Compras/Pagos/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult AnularPago(int id, [FromBody] MotivoDto m)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            try { new Compras().AnularPago(id, m == null ? null : m.Motivo, idUsuario); return Ok(); }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo anular el pago.")); }
        }

        private string TraducirErrorSql(SqlException ex, string mensajeGenerico)
        {
            if (ex.Number >= 50000) return ex.Message;
            if (ex.Number == 547) return mensajeGenerico + " Algún dato referenciado no existe o no es válido.";
            return mensajeGenerico + " Intentalo de nuevo o avisá a sistemas.";
        }

        private int ObtenerIdUsuarioActual()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;
            var claim = identity.FindFirst(ClaimTypes.NameIdentifier) ?? identity.FindFirst("sub") ?? identity.FindFirst("Sub");
            int id;
            return (claim != null && int.TryParse(claim.Value, out id)) ? id : 0;
        }
    }
}

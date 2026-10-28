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
    public class NotasClienteController : ApiController
    {
        // GET api/NotasCliente/Venta/5 — la venta con lo que se puede devolver
        [HttpGet, Route("api/NotasCliente/Venta/{id:int}")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult ParaDevolucion(int id)
        {
            DataSet ds = new NotaCliente().ParaDevolucion(id);
            if (ds.Tables.Count < 3 || ds.Tables[0].Rows.Count == 0) return NotFound();
            return Ok(new { Venta = ds.Tables[0], Renglones = ds.Tables[1], Notas = ds.Tables[2] });
        }

        // Cuentas desde las que se puede reintegrar
        [HttpGet, Route("api/NotasCliente/Cuentas")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public DataTable Cuentas()
        {
            return new MovimientoEspecial().CuentasDisponibles();
        }

        [HttpPost, Route("api/NotasCliente/Credito")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Credito([FromBody] NotaCreditoClienteDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null) return BadRequest("Faltan los datos de la nota de crédito.");
            try
            {
                DataTable dt = new NotaCliente().Credito(d, idUsuario);
                int idNota = Convert.ToInt32(dt.Rows[0]["IdNota"]);
                // Su nota de credito fiscal (script 92), asociada a la factura
                object comprobante = Comprobante.IntentarDesdeNota(idNota, idUsuario);
                return Ok(new { IdNota = idNota, Importe = dt.Rows[0]["Importe"], Comprobante = comprobante });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la nota de crédito.")); }
        }

        [HttpPost, Route("api/NotasCliente/Debito")]
        [AuthorizeJwt(Roles = "Dueño,Administrador")]
        public IHttpActionResult Debito([FromBody] NotaDebitoClienteDto d)
        {
            int idUsuario = ObtenerIdUsuarioActual();
            if (idUsuario <= 0) return Unauthorized();
            if (d == null || d.IdCliente <= 0) return BadRequest("Faltan los datos de la nota de débito.");
            try
            {
                int idNota = Convert.ToInt32(new NotaCliente().Debito(d, idUsuario));
                object comprobante = Comprobante.IntentarDesdeNota(idNota, idUsuario);
                return Ok(new { IdNota = idNota, Comprobante = comprobante });
            }
            catch (SqlException ex) { return BadRequest(TraducirErrorSql(ex, "No se pudo registrar la nota de débito.")); }
        }

        [HttpGet, Route("api/NotasCliente")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable Listar(DateTime? desde = null, DateTime? hasta = null)
        {
            return new NotaCliente().Listar(desde, hasta);
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

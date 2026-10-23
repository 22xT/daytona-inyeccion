using System;
using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Inventario fisico (script 79). Contar lo puede hacer el mostrador;
       cerrar (ajustar el stock) y anular, solo quien puede ajustar. */
    [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
    public class InventarioController : ApiController
    {
        public class IniciarDto { public int? IdRubro { get; set; } public string Observacion { get; set; } }
        public class ContarDto { public int IdRepuesto { get; set; } public int? Contado { get; set; } }
        public class MotivoDto { public string Motivo { get; set; } }
        public class CerrarDto { public string MotivoGeneral { get; set; } }

        // GET api/Inventario — historial
        [HttpGet, Route("api/Inventario")]
        public DataTable Lista() { return new Inventario().Lista(); }

        // GET api/Inventario/Abierto — el conteo en curso (sin el stock del sistema)
        [HttpGet, Route("api/Inventario/Abierto")]
        public IHttpActionResult Abierto() { return Detalle(null); }

        // GET api/Inventario/5
        [HttpGet, Route("api/Inventario/{id:int}")]
        public IHttpActionResult Get(int id) { return Detalle(id); }

        private IHttpActionResult Detalle(int? id)
        {
            DataSet ds = new Inventario().Get(id);
            if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0) return Ok(new { Conteo = (object)null });
            return Ok(new { Conteo = ds.Tables[0], Renglones = ds.Tables.Count > 1 ? ds.Tables[1] : null });
        }

        // POST api/Inventario — empezar un conteo
        [HttpPost, Route("api/Inventario")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Iniciar([FromBody] IniciarDto d)
        {
            return Intentar(() => Ok(new Inventario().Iniciar(d != null ? d.IdRubro : null, IdUsuario(), d != null ? d.Observacion : null)),
                            "No se pudo empezar el conteo.");
        }

        // PUT api/Inventario/5/Contar — anotar lo contado (Contado null = borrar)
        [HttpPut, Route("api/Inventario/{id:int}/Contar")]
        public IHttpActionResult Contar(int id, [FromBody] ContarDto d)
        {
            if (d == null || d.IdRepuesto <= 0) return BadRequest("Falta el repuesto.");
            return Intentar(() => Ok(new Inventario().Contar(id, d.IdRepuesto, d.Contado, IdUsuario())), "No se pudo anotar la cantidad.");
        }

        // GET api/Inventario/5/Diferencias
        [HttpGet, Route("api/Inventario/{id:int}/Diferencias")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Diferencias(int id)
        {
            return Intentar(() =>
            {
                DataSet ds = new Inventario().Diferencias(id);
                return Ok(new { Resumen = ds.Tables[0], Diferencias = ds.Tables[1] });
            }, "No se pudieron calcular las diferencias.");
        }

        // PUT api/Inventario/Renglon/9/Motivo
        [HttpPut, Route("api/Inventario/Renglon/{idRenglon:int}/Motivo")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Motivo(int idRenglon, [FromBody] MotivoDto d)
        {
            string m = d != null && d.Motivo != null ? d.Motivo.Trim() : null;
            if (m != null && m.Length > 200) return BadRequest("El motivo no puede superar los 200 caracteres.");
            return Intentar(() => { new Inventario().Motivo(idRenglon, m); return Ok(); }, "No se pudo guardar el motivo.");
        }

        // POST api/Inventario/5/Cerrar — ajusta el stock de las diferencias
        [HttpPost, Route("api/Inventario/{id:int}/Cerrar")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Cerrar(int id, [FromBody] CerrarDto d)
        {
            string m = d != null && d.MotivoGeneral != null ? d.MotivoGeneral.Trim() : null;
            if (m != null && m.Length > 200) return BadRequest("El motivo no puede superar los 200 caracteres.");
            return Intentar(() => Ok(new Inventario().Cerrar(id, IdUsuario(), m)), "No se pudo cerrar el conteo.");
        }

        // POST api/Inventario/5/Anular
        [HttpPost, Route("api/Inventario/{id:int}/Anular")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Anular(int id)
        {
            return Intentar(() => { new Inventario().Anular(id, IdUsuario()); return Ok(); }, "No se pudo anular el conteo.");
        }

        private IHttpActionResult Intentar(Func<IHttpActionResult> accion, string mensaje)
        {
            try { return accion(); }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest(mensaje + " " + ex.Message);
            }
        }

        private int IdUsuario()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;
            var claim = identity.FindFirst(ClaimTypes.NameIdentifier) ?? identity.FindFirst("sub") ?? identity.FindFirst("Sub");
            int id;
            return (claim != null && int.TryParse(claim.Value, out id)) ? id : 0;
        }
    }
}

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
    /* Matcher, entregable 1 (script 86): pantalla para armar el
       conjunto de pares confirmados. Solo Dueño y Administrador. */
    [AuthorizeJwt(Roles = "Dueño,Administrador")]
    public class MatcherController : ApiController
    {
        private static readonly string[] Relaciones = { "PENDIENTE", "IGUAL", "EQUIVALENTE", "DISTINTO" };

        // GET api/Matcher/Tipos
        [HttpGet, Route("api/Matcher/Tipos")]
        public IHttpActionResult Tipos()
        {
            try { return Ok(new Matcher().Tipos()); }
            catch (SqlException ex) { return BadRequest("No se pudieron leer los tipos de pieza. " + ex.Message); }
        }

        // GET api/Matcher/Ancla?tipo=PASTILLAS DE FRENO   (la proxima)
        // GET api/Matcher/Ancla?id=1234                    (una ya etiquetada)
        [HttpGet, Route("api/Matcher/Ancla")]
        public IHttpActionResult Ancla(string tipo = null, int? id = null)
        {
            if (string.IsNullOrWhiteSpace(tipo) && !id.HasValue) return BadRequest("Elegí un tipo de pieza.");
            try
            {
                DataSet ds = new Matcher().Ancla(tipo, id);
                DataTable a = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable();
                if (a.Rows.Count == 0) return Ok(new { Ancla = (object)null, Marcados = new DataTable() });
                return Ok(new { Ancla = a, Marcados = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable() });
            }
            catch (SqlException ex) { return BadRequest("No se pudo traer el artículo. " + ex.Message); }
        }

        // GET api/Matcher/Candidatos?texto=pastilla cerato
        [HttpGet, Route("api/Matcher/Candidatos")]
        public IHttpActionResult Candidatos(string texto)
        {
            if (string.IsNullOrWhiteSpace(texto) || texto.Trim().Length < 3) return Ok(new DataTable());
            try { return Ok(new Matcher().Candidatos(texto.Trim())); }
            catch (SqlException ex) { return BadRequest("No se pudo buscar. " + ex.Message); }
        }

        public class EtiquetarDto
        {
            public int IdAncla { get; set; }
            public string Estado { get; set; }
            public List<Matcher.ParDto> Pares { get; set; }
            public string Nota { get; set; }
        }

        // POST api/Matcher/Etiquetar
        [HttpPost, Route("api/Matcher/Etiquetar")]
        public IHttpActionResult Etiquetar([FromBody] EtiquetarDto d)
        {
            if (d == null || d.IdAncla <= 0) return BadRequest("Falta el artículo.");
            string estado = (d.Estado ?? "ETIQUETADA").Trim().ToUpperInvariant();
            if (estado != "ETIQUETADA" && estado != "SALTEADA") return BadRequest("Estado no válido.");
            try
            {
                int n = new Matcher().Etiquetar(d.IdAncla, estado, d.Pares, d.Nota, IdUsuario());
                return Ok(new { ParesGuardados = n });
            }
            catch (SqlException ex) { return BadRequest(ex.Message); }
        }

        // GET api/Matcher/Codigo
        [HttpGet, Route("api/Matcher/Codigo")]
        public IHttpActionResult Codigo()
        {
            try { return Ok(new Matcher().ParesCodigo()); }
            catch (SqlException ex) { return BadRequest("No se pudieron leer los pares. " + ex.Message); }
        }

        public class RevisarDto { public string Relacion { get; set; } }

        // PUT api/Matcher/Codigo/15  { "Relacion": "DISTINTO" }
        [HttpPut, Route("api/Matcher/Codigo/{id:int}")]
        public IHttpActionResult RevisarCodigo(int id, [FromBody] RevisarDto d)
        {
            string rel = d == null || d.Relacion == null ? "" : d.Relacion.Trim().ToUpperInvariant();
            if (Array.IndexOf(Relaciones, rel) < 0) return BadRequest("Relación no válida.");
            try { new Matcher().RevisarCodigo(id, rel, IdUsuario()); return Ok(); }
            catch (SqlException ex) { return BadRequest(ex.Message); }
        }

        // GET api/Matcher/Resumen
        [HttpGet, Route("api/Matcher/Resumen")]
        public IHttpActionResult Resumen()
        {
            try
            {
                DataSet ds = new Matcher().Resumen();
                return Ok(new
                {
                    Totales = ds.Tables.Count > 0 ? ds.Tables[0] : new DataTable(),
                    Ultimas = ds.Tables.Count > 1 ? ds.Tables[1] : new DataTable()
                });
            }
            catch (SqlException ex) { return BadRequest("No se pudo leer el avance. " + ex.Message); }
        }

        private int IdUsuario()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;
            var claim = identity.FindFirst(ClaimTypes.NameIdentifier) ?? identity.FindFirst("sub");
            int id;
            return claim != null && int.TryParse(claim.Value, out id) ? id : 0;
        }
    }
}

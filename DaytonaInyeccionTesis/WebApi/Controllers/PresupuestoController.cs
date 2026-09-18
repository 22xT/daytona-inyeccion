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
    public class PresupuestoController : ApiController
    {
        // GET: api/Presupuesto
        // GET: api/Presupuesto?estado=Vigente&texto=juan&desde=2026-01-01
        // Un solo GET con parametros opcionales. Si no viene ninguno, lista todo.
        // No puede haber dos acciones GET en la misma ruta: Web API no sabria
        // cual elegir, y Swagger directamente falla al generar el doc.
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(string desde = null, string hasta = null,
                             int idCliente = 0, string estado = null, string texto = null)
        {
            Presupuesto oPresupuesto = new Presupuesto();

            bool sinFiltros = string.IsNullOrEmpty(desde)
                           && string.IsNullOrEmpty(hasta)
                           && idCliente <= 0
                           && string.IsNullOrEmpty(estado)
                           && string.IsNullOrEmpty(texto);

            if (sinFiltros)
                return oPresupuesto.ListarTodos();

            DateTime fd, fh;
            DateTime? fechaDesde = DateTime.TryParse(desde, out fd) ? (DateTime?)fd : null;
            DateTime? fechaHasta = DateTime.TryParse(hasta, out fh) ? (DateTime?)fh : null;

            return oPresupuesto.Filtrar(fechaDesde, fechaHasta, idCliente, estado, texto);
        }

        // GET: api/Presupuesto/5  (cabecera + detalle)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataSet Get(int id)
        {
            Presupuesto oPresupuesto = new Presupuesto();
            oPresupuesto.Id = id;
            return oPresupuesto.ListarPorId();
        }

        // POST: api/Presupuesto
        // Devuelve { Id, Numero }: el Numero es el que se imprime en el papel.
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Post([FromBody] Presupuesto presupuesto)
        {
            string error = ValidarPresupuesto(presupuesto);
            if (error != "")
                return BadRequest(error);

            presupuesto.IdUsuario = ObtenerIdUsuarioActual();
            if (presupuesto.IdUsuario <= 0)
                return BadRequest("No se pudo identificar al usuario de la sesion.");

            try
            {
                presupuesto.Guardar();
                return Ok(new { Id = presupuesto.Id, Numero = presupuesto.Numero });
            }
            catch (SqlException ex)
            {
                if (ex.Number == 547)
                    return BadRequest("El cliente indicado no existe.");

                return BadRequest("No se pudo guardar el presupuesto. " + ex.Message);
            }
        }

        // PUT: api/Presupuesto/5  (vincular con la venta que lo concreto)
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor,Sistema")]
        public IHttpActionResult Put(int id, [FromBody] Presupuesto presupuesto)
        {
            if (id <= 0)
                return BadRequest("El identificador del presupuesto no es valido.");

            if (presupuesto == null)
                return BadRequest("No se recibieron datos del presupuesto.");

            if (!presupuesto.IdVenta.HasValue || presupuesto.IdVenta.Value <= 0)
                return BadRequest("Debe indicar la venta con la que se vincula el presupuesto.");

            Presupuesto oPresupuesto = new Presupuesto();
            oPresupuesto.Id = id;

            try
            {
                oPresupuesto.VincularVenta(presupuesto.IdVenta.Value);
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo vincular el presupuesto. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Presupuesto/5
        // Es baja LOGICA, no borrado fisico: el presupuesto queda como Anulado.
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor")]
        public IHttpActionResult Delete(int id)
        {
            if (id <= 0)
                return BadRequest("El identificador del presupuesto no es valido.");

            Presupuesto oPresupuesto = new Presupuesto();
            oPresupuesto.Id = id;

            try
            {
                oPresupuesto.Anular();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo anular el presupuesto. " + ex.Message);
            }

            return Ok();
        }

        // Un presupuesto NO exige cliente: por eso solo se valida si vino uno.
        private string ValidarPresupuesto(Presupuesto presupuesto)
        {
            if (presupuesto == null)
                return "No se recibieron datos del presupuesto.";

            if (!string.IsNullOrEmpty(presupuesto.NombreOcasional) && presupuesto.NombreOcasional.Length > 80)
                return "El nombre no puede superar los 80 caracteres.";

            if (!string.IsNullOrEmpty(presupuesto.TelefonoOcasional) && presupuesto.TelefonoOcasional.Length > 30)
                return "El telefono no puede superar los 30 caracteres.";

            if (!string.IsNullOrEmpty(presupuesto.Observaciones) && presupuesto.Observaciones.Length > 300)
                return "Las observaciones no pueden superar los 300 caracteres.";

            if (!string.IsNullOrEmpty(presupuesto.TipoCliente)
                && presupuesto.TipoCliente != "Publico" && presupuesto.TipoCliente != "Mecanico")
                return "El tipo de cliente debe ser Publico o Mecanico.";

            if (presupuesto.DiasValidez < 0 || presupuesto.DiasValidez > 365)
                return "Los dias de validez deben estar entre 0 y 365.";

            // Si mandaron un cliente, verificamos que exista y este activo
            if (presupuesto.IdCliente.HasValue && presupuesto.IdCliente.Value > 0)
            {
                Cliente oCliente = new Cliente();
                oCliente.Id = presupuesto.IdCliente.Value;
                DataTable dt = oCliente.ListarPorId();

                if (dt == null || dt.Rows.Count == 0)
                    return "El cliente seleccionado no existe.";

                bool activo = Convert.ToBoolean(dt.Rows[0]["Activo"]);
                if (!activo)
                    return "El cliente seleccionado esta dado de baja. Reactivalo o elegi otro.";
            }

            return "";
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

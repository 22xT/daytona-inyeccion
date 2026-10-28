using System;
using System.Data;
using System.Data.SqlClient;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class MovimientoCajaController : ApiController
    {
        // GET: api/MovimientoCaja  (historial) — Admin, Vendedor, Dueño
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor,Dueño")]
        public DataTable Get()
        {
            MovimientoCaja oCaja = new MovimientoCaja();
            DataTable tabla = oCaja.ListarTodos();

            // Arqueo ciego (script 94): con la caja abierta no se ven los
            // movimientos del turno, si no el cierre deja de ser ciego
            DateTime? apertura = AperturaCiega();
            if (apertura.HasValue && tabla.Columns.Contains("Fecha"))
            {
                for (int i = tabla.Rows.Count - 1; i >= 0; i--)
                {
                    object f = tabla.Rows[i]["Fecha"];
                    if (f != DBNull.Value && Convert.ToDateTime(f) >= apertura.Value) tabla.Rows.RemoveAt(i);
                }
            }
            return tabla;
        }

        // GET: api/MovimientoCaja/Saldo  (saldo actual + totales del dia)
        [HttpGet]
        [Route("api/MovimientoCaja/Saldo")]
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor,Dueño")]
        public DataTable GetSaldo()
        {
            MovimientoCaja oCaja = new MovimientoCaja();
            DataTable tabla = oCaja.ObtenerSaldo();

            // Arqueo ciego: el saldo y los totales del dia se ven al cerrar
            if (AperturaCiega().HasValue)
            {
                foreach (DataColumn col in tabla.Columns)
                {
                    if (col.ColumnName != "SaldoActual" && col.ColumnName != "IngresosHoy" && col.ColumnName != "EgresosHoy") continue;
                    col.ReadOnly = false;
                    col.AllowDBNull = true;
                    foreach (DataRow r in tabla.Rows) r[col] = DBNull.Value;
                }
            }
            return tabla;
        }

        // Fecha de apertura si la caja esta abierta y el usuario cierra a ciegas; si no, null
        private DateTime? AperturaCiega()
        {
            if (SesionCajaController.VeTeorico(User.Identity as ClaimsIdentity)) return null;
            DataTable s = new SesionCaja().Actual(false);
            if (s.Rows.Count == 0 || !Convert.ToBoolean(s.Rows[0]["Abierta"])) return null;
            return Convert.ToDateTime(s.Rows[0]["FechaApertura"]);
        }

        // POST: api/MovimientoCaja  (registrar) — Admin y Vendedor
        [AuthorizeJwt(Roles = "Administrador,Vendedor")]
        public IHttpActionResult Post([FromBody] MovimientoCaja mov)
        {
            return BadRequest("Los movimientos manuales se registran como gasto o como movimiento especial.");
            string error = Validar(mov);
            if (error != "")
                return BadRequest(error);

            int idUsuario = ObtenerIdUsuario();
            if (idUsuario == 0)
                return BadRequest("No se pudo identificar al usuario de la sesión.");

            mov.IdUsuario = idUsuario;

            try
            {
                mov.Registrar();
            }
            catch (SqlException ex)
            {
                return BadRequest(ex.Message);
            }

            return Ok();
        }

        private int ObtenerIdUsuario()
        {
            var identity = User.Identity as ClaimsIdentity;
            if (identity == null) return 0;

            var claim = identity.FindFirst(ClaimTypes.NameIdentifier)
                        ?? identity.FindFirst(JwtRegisteredClaimNames.Sub)
                        ?? identity.FindFirst("sub");

            if (claim == null) return 0;

            int id;
            return int.TryParse(claim.Value, out id) ? id : 0;
        }

        private string Validar(MovimientoCaja mov)
        {
            if (mov == null)
                return "No se recibieron datos del movimiento.";

            if (string.IsNullOrWhiteSpace(mov.Tipo) || (mov.Tipo != "Ingreso" && mov.Tipo != "Egreso"))
                return "El tipo debe ser Ingreso o Egreso.";

            if (string.IsNullOrWhiteSpace(mov.Concepto))
                return "El concepto es obligatorio.";

            if (mov.Monto <= 0)
                return "El monto debe ser mayor a cero.";

            if (mov.Descripcion != null && mov.Descripcion.Length > 250)
                return "La descripción no puede superar los 250 caracteres.";

            return "";
        }
    }
}
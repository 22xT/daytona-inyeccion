using System.Data;
using System.Data.SqlClient;
using System.Security.Claims;
using System.Text.RegularExpressions;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ClienteController : ApiController
    {
        // GET: api/Cliente  (Dueño, Administrador, Supervisor, Vendedor)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get()
        {
            Cliente oCliente = new Cliente();
            return oCliente.ListarTodos();
        }

        // GET: api/Cliente/5  (Dueño, Administrador, Supervisor, Vendedor)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(int id)
        {
            Cliente oCliente = new Cliente();
            oCliente.Id = id;
            return oCliente.ListarPorId();
        }

        // GET: api/Cliente/5/Credito — saldo, limite, disponible y deuda atrasada (script 82)
        [HttpGet]
        [Route("api/Cliente/{id:int}/Credito")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Credito(int id)
        {
            Cliente oCliente = new Cliente();
            oCliente.Id = id;
            DataSet ds = oCliente.Credito();
            if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                return NotFound();
            return Ok(new
            {
                Situacion = ds.Tables[0],
                Autorizaciones = ds.Tables.Count > 1 ? ds.Tables[1] : null
            });
        }

        // POST: api/Cliente  (Dueño, Administrador, Supervisor, Vendedor)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Post([FromBody] Cliente cliente)
        {
            string error = ValidarCliente(cliente);
            if (error != "")
                return BadRequest(error);

            NormalizarCliente(cliente);
            PermisoCredito(cliente);

            try
            {
                int idNuevo = cliente.Guardar();
                // Se devuelve el Id para poder dejarlo seleccionado en la venta
                return Ok(new { Id = idNuevo });
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un cliente con ese DNI.");

                if (ex.Number >= 50000)
                    return BadRequest(ex.Message);

                return BadRequest("No se pudo guardar el cliente. " + ex.Message);
            }
        }

        // PUT: api/Cliente/5  (Dueño, Administrador, Supervisor, Vendedor)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Put(int id, [FromBody] Cliente cliente)
        {
            string error = ValidarCliente(cliente);
            if (error != "")
                return BadRequest(error);

            NormalizarCliente(cliente);
            PermisoCredito(cliente);
            cliente.Id = id;

            try
            {
                cliente.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un cliente con ese DNI.");

                if (ex.Number >= 50000)
                    return BadRequest(ex.Message);

                return BadRequest("No se pudo editar el cliente. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Cliente/5  (Administrador, Supervisor, Vendedor)
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Delete(int id)
        {
            Cliente oCliente = new Cliente();
            oCliente.Id = id;

            try
            {
                oCliente.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el cliente. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Cliente/5/Activar  (Administrador, Supervisor, Vendedor)
        [HttpPut]
        [Route("api/Cliente/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor")]
        public IHttpActionResult Activar(int id)
        {
            Cliente oCliente = new Cliente();
            oCliente.Id = id;

            try
            {
                oCliente.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo activar el cliente. " + ex.Message);
            }

            return Ok();
        }

        private string ValidarCliente(Cliente cliente)
        {
            if (cliente == null)
                return "No se recibieron datos del cliente.";

            // DNI: OPCIONAL. En el mostrador no se le pide el documento al
            // mecanico. Si lo cargan, se valida igual que antes.
            if (!string.IsNullOrWhiteSpace(cliente.Dni))
            {
                string dni = cliente.Dni.Trim();

                if (dni.Length < 7 || dni.Length > 8)
                    return "El DNI debe tener 7 u 8 dígitos.";

                foreach (char c in dni)
                {
                    if (!char.IsDigit(c))
                        return "El DNI debe contener solo números, sin puntos ni espacios.";
                }
            }

            // Un mecanico sin telefono no se puede ubicar ni reclamar.
            // Es la misma regla que el CHECK de la base, pero con mensaje claro.
            if (cliente.EsMecanico && string.IsNullOrWhiteSpace(cliente.Telefono))
                return "El teléfono es obligatorio para un mecánico: es el dato con el que lo vas a encontrar y contactar.";

            // Nombre: obligatorio, solo letras
            if (string.IsNullOrWhiteSpace(cliente.Nombre))
                return "El nombre es obligatorio.";

            if (!SoloLetras(cliente.Nombre))
                return "El nombre solo puede contener letras.";

            // Apellido: obligatorio, solo letras
            if (string.IsNullOrWhiteSpace(cliente.Apellido))
                return "El apellido es obligatorio.";

            if (!SoloLetras(cliente.Apellido))
                return "El apellido solo puede contener letras.";

            // Telefono: opcional; si se carga, un celular argentino valido (28/10).
            // Se guarda con formato: "351 7585566"
            if (!string.IsNullOrWhiteSpace(cliente.Telefono))
            {
                string tel = Telefono.Formatear(cliente.Telefono);
                if (tel == null) return Telefono.Error;
                cliente.Telefono = tel;
            }

            // Mail: opcional; si se carga, formato real
            if (!string.IsNullOrWhiteSpace(cliente.Mail))
            {
                if (!Regex.IsMatch(cliente.Mail, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
                    return "El correo no es válido. Debe tener el formato nombre@dominio.com";
            }

            // Calle: opcional; si se carga, sin caracteres raros
            if (!string.IsNullOrWhiteSpace(cliente.Calle))
            {
                foreach (char c in cliente.Calle)
                {
                    if (!char.IsLetterOrDigit(c) && c != ' ' && c != '.' && c != '°' && c != '-')
                        return "La calle contiene caracteres no válidos.";
                }
            }

            // Numero: opcional; si se carga, sin caracteres raros
            if (!string.IsNullOrWhiteSpace(cliente.Numero))
            {
                if (cliente.Numero.Length > 15)
                    return "El número de calle es demasiado largo.";

                foreach (char c in cliente.Numero)
                {
                    if (!char.IsLetterOrDigit(c) && c != ' ' && c != '/' && c != '-')
                        return "El número de calle contiene caracteres no válidos.";
                }
            }

            if (cliente.LimiteCredito.HasValue && (cliente.LimiteCredito.Value < 0 || cliente.LimiteCredito.Value > 1000000000m))
                return "El límite de crédito tiene que ser un monto entre 0 y 1.000.000.000. Vacío = sin límite.";

            // Datos fiscales (script 92): deciden si le corresponde factura A o B
            if (!string.IsNullOrWhiteSpace(cliente.CondicionIva))
            {
                string cond = cliente.CondicionIva.Trim();
                if (System.Array.IndexOf(CondicionesIva, cond) < 0)
                    return "La condición frente al IVA no es válida.";
                cliente.CondicionIva = cond;

                if (!string.IsNullOrWhiteSpace(cliente.Cuit))
                {
                    string cuit = CuitNormalizado(cliente.Cuit);
                    if (cuit == null) return "El CUIT no es válido: revisá los 11 números.";
                    cliente.Cuit = cuit;
                }
                else if (cond != "Consumidor Final")
                    return "Para un cliente " + cond + " el CUIT es obligatorio.";

                if (!string.IsNullOrWhiteSpace(cliente.RazonSocial) && cliente.RazonSocial.Trim().Length > 120)
                    return "La razón social puede tener hasta 120 caracteres.";
            }

            return "";
        }

        private static readonly string[] CondicionesIva =
            { "Consumidor Final", "Responsable Inscripto", "Monotributo", "Exento" };

        // 11 digitos con el verificador correcto (modulo 11). Acepta guiones,
        // puntos y espacios. Devuelve los 11 digitos o null.
        public static string CuitNormalizado(string cuit)
        {
            if (cuit == null) return null;
            string c = Regex.Replace(cuit, @"[\s\.\-]", "");
            if (!Regex.IsMatch(c, @"^\d{11}$")) return null;
            int[] pesos = { 5, 4, 3, 2, 7, 6, 5, 4, 3, 2 };
            int suma = 0;
            for (int i = 0; i < 10; i++) suma += (c[i] - '0') * pesos[i];
            int dv = 11 - (suma % 11);
            if (dv == 11) dv = 0;
            if (dv == 10 || dv != c[10] - '0') return null;
            return c;
        }

        // El limite de credito solo lo cambia el Dueño o un Administrador.
        // Lo que mande otro rol se ignora (no se pisa nada).
        private void PermisoCredito(Cliente cliente)
        {
            var identity = User.Identity as ClaimsIdentity;
            var rol = identity == null ? null : identity.FindFirst(ClaimTypes.Role);
            bool puede = rol != null && (rol.Value == "Dueño" || rol.Value == "Administrador");
            cliente.CambiarCredito = puede && cliente.CambiarLimite;
            if (!cliente.CambiarCredito) cliente.LimiteCredito = null;
        }

        // El DNI vacio tiene que quedar NULL, no "".
        // El indice unico filtrado ignora los NULL, pero dos "" son iguales
        // entre si y chocarian contra el indice al cargar el segundo cliente.
        private void NormalizarCliente(Cliente cliente)
        {
            if (string.IsNullOrWhiteSpace(cliente.Dni))
                cliente.Dni = null;
            else
                cliente.Dni = cliente.Dni.Trim();

            if (string.IsNullOrWhiteSpace(cliente.Telefono)) cliente.Telefono = null;
            if (string.IsNullOrWhiteSpace(cliente.Mail)) cliente.Mail = null;
            if (string.IsNullOrWhiteSpace(cliente.Calle)) cliente.Calle = null;
            if (string.IsNullOrWhiteSpace(cliente.Numero)) cliente.Numero = null;

            if (!string.IsNullOrWhiteSpace(cliente.Nombre)) cliente.Nombre = cliente.Nombre.Trim();
            if (!string.IsNullOrWhiteSpace(cliente.Apellido)) cliente.Apellido = cliente.Apellido.Trim();
        }

        // Solo letras (incluye acentos y ñ) y espacios.
        private bool SoloLetras(string texto)
        {
            foreach (char c in texto)
            {
                if (!char.IsLetter(c) && c != ' ')
                    return false;
            }
            return true;
        }
    }
}
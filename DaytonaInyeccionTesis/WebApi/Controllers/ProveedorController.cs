using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web.Http;
using WebApi.Models;
using WebApi.Filters;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class ProveedorController : ApiController
    {
        // Lista blanca de condiciones de IVA validas
        private static readonly string[] CondicionesIvaValidas =
            { "Responsable Inscripto", "Monotributista", "Exento", "Consumidor Final" };

        // GET: api/Proveedor
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get()
        {
            Proveedor oProveedor = new Proveedor();
            return oProveedor.ListarTodos();
        }

        // GET: api/Proveedor/5
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor")]
        public DataTable Get(int id)
        {
            Proveedor oProveedor = new Proveedor();
            oProveedor.Id = id;
            return oProveedor.ListarPorId();
        }

        // POST: api/Proveedor  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Post([FromBody] Proveedor proveedor)
        {
            Limpiar(proveedor);
            string error = ValidarProveedor(proveedor);
            if (error != "")
                return BadRequest(error);

            try
            {
                proveedor.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un proveedor con ese CUIT.");

                return BadRequest("No se pudo guardar el proveedor. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Proveedor/5  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Put(int id, [FromBody] Proveedor proveedor)
        {
            if (id <= 0)
                return BadRequest("El identificador del proveedor no es válido.");

            Limpiar(proveedor);
            string error = ValidarProveedor(proveedor);
            if (error != "")
                return BadRequest(error);

            proveedor.Id = id;

            try
            {
                proveedor.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un proveedor con ese CUIT.");

                return BadRequest("No se pudo editar el proveedor. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Proveedor/5  (solo Administrador)
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Delete(int id)
        {
            if (id <= 0)
                return BadRequest("El identificador del proveedor no es válido.");

            Proveedor oProveedor = new Proveedor();
            oProveedor.Id = id;

            try
            {
                oProveedor.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el proveedor. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Proveedor/5/Activar  (solo Administrador)
        [HttpPut]
        [Route("api/Proveedor/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador")]
        public IHttpActionResult Activar(int id)
        {
            if (id <= 0)
                return BadRequest("El identificador del proveedor no es válido.");

            Proveedor oProveedor = new Proveedor();
            oProveedor.Id = id;

            try
            {
                oProveedor.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo activar el proveedor. " + ex.Message);
            }

            return Ok();
        }

        // ====================================================================
        // Limpieza: Trim a todos los strings y vacios -> null
        // ====================================================================
        private void Limpiar(Proveedor p)
        {
            if (p == null) return;
            p.Cuit = Limpia(p.Cuit);
            p.RazonSocial = Limpia(p.RazonSocial);
            p.CondicionIva = Limpia(p.CondicionIva);
            p.Calle = Limpia(p.Calle);
            p.Numero = Limpia(p.Numero);
            p.Barrio = Limpia(p.Barrio);
            p.Localidad = Limpia(p.Localidad);
            p.Provincia = Limpia(p.Provincia);
            p.CodigoPostal = Limpia(p.CodigoPostal);
            p.Telefono = Limpia(p.Telefono);
            p.Mail = Limpia(p.Mail);
            p.Observaciones = Limpia(p.Observaciones);
        }

        private string Limpia(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return null;
            return s.Trim();
        }

        // ====================================================================
        // Validacion completa del proveedor. Devuelve "" si esta todo bien.
        // ====================================================================
        private string ValidarProveedor(Proveedor proveedor)
        {
            if (proveedor == null)
                return "No se recibieron datos del proveedor.";

            // ---------- CUIT ----------
            if (string.IsNullOrWhiteSpace(proveedor.Cuit))
                return "El CUIT es obligatorio.";

            if (proveedor.Cuit.Length != 11)
                return "El CUIT debe tener exactamente 11 dígitos.";

            if (!proveedor.Cuit.All(char.IsDigit))
                return "El CUIT debe contener solo números, sin guiones ni espacios.";

            if (!ValidarCuitArgentino(proveedor.Cuit))
                return "El CUIT no es válido (dígito verificador incorrecto).";

            // ---------- Razon social ----------
            if (string.IsNullOrWhiteSpace(proveedor.RazonSocial))
                return "La razón social es obligatoria.";

            if (proveedor.RazonSocial.Length < 3)
                return "La razón social debe tener al menos 3 caracteres.";

            if (proveedor.RazonSocial.Length > 100)
                return "La razón social no puede superar los 100 caracteres.";

            if (proveedor.RazonSocial.All(char.IsDigit))
                return "La razón social no puede ser solo números.";

            if (Regex.IsMatch(proveedor.RazonSocial, @"[<>{}\\^~`|]"))
                return "La razón social contiene caracteres no válidos.";

            // ---------- Condicion IVA ----------
            if (string.IsNullOrWhiteSpace(proveedor.CondicionIva))
                return "Debe seleccionar una condición frente al IVA.";

            if (!CondicionesIvaValidas.Contains(proveedor.CondicionIva))
                return "La condición frente al IVA seleccionada no es válida.";

            // ---------- Provincia ----------
            if (string.IsNullOrWhiteSpace(proveedor.Provincia))
                return "Debe seleccionar una provincia.";

            if (proveedor.Provincia.Length > 50)
                return "El nombre de la provincia es demasiado largo.";

            // ---------- Localidad ----------
            if (string.IsNullOrWhiteSpace(proveedor.Localidad))
                return "Debe ingresar o seleccionar una localidad.";

            if (proveedor.Localidad.Length < 2)
                return "La localidad debe tener al menos 2 caracteres.";

            if (proveedor.Localidad.Length > 80)
                return "La localidad es demasiado larga.";

            // ---------- Codigo postal (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.CodigoPostal))
            {
                if (proveedor.CodigoPostal.Length > 10)
                    return "El código postal no puede superar los 10 caracteres.";

                if (!proveedor.CodigoPostal.All(char.IsLetterOrDigit))
                    return "El código postal solo puede contener letras y números.";
            }

            // ---------- Calle (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.Calle))
            {
                if (proveedor.Calle.Length < 2)
                    return "La calle debe tener al menos 2 caracteres.";

                if (Regex.IsMatch(proveedor.Calle, @"[<>{}\\^~`|]"))
                    return "La calle contiene caracteres no válidos.";
            }

            // ---------- Numero (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.Numero))
            {
                if (!Regex.IsMatch(proveedor.Numero, @"^[A-Za-z0-9/\- ]+$"))
                    return "El número de calle solo admite dígitos, letras, / y -.";
            }

            // ---------- Barrio (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.Barrio))
            {
                if (proveedor.Barrio.Length < 2)
                    return "El barrio debe tener al menos 2 caracteres.";
            }

            // ---------- Telefono (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.Telefono))
            {
                if (!Regex.IsMatch(proveedor.Telefono, @"^[0-9+\-() ]+$"))
                    return "El teléfono solo puede contener números y los signos + - ( ).";

                int digitos = proveedor.Telefono.Count(char.IsDigit);
                if (digitos < 6)
                    return "El teléfono debe tener al menos 6 dígitos.";
            }

            // ---------- Mail (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.Mail))
            {
                if (!Regex.IsMatch(proveedor.Mail, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
                    return "El correo no es válido. Debe tener el formato nombre@dominio.com";
            }

            // ---------- Observaciones (opcional) ----------
            if (!string.IsNullOrWhiteSpace(proveedor.Observaciones))
            {
                if (proveedor.Observaciones.Length > 200)
                    return "Las observaciones no pueden superar los 200 caracteres.";
            }

            return "";
        }

        // ====================================================================
        // Validacion real del CUIT argentino con digito verificador
        // ====================================================================
        private bool ValidarCuitArgentino(string cuit)
        {
            if (string.IsNullOrEmpty(cuit) || cuit.Length != 11 || !cuit.All(char.IsDigit))
                return false;

            // Rechazar todos los digitos iguales (00000000000, 11111111111, etc.)
            if (cuit.Distinct().Count() == 1)
                return false;

            int[] mult = { 5, 4, 3, 2, 7, 6, 5, 4, 3, 2 };
            int suma = 0;
            for (int i = 0; i < 10; i++)
                suma += (cuit[i] - '0') * mult[i];

            int resto = suma % 11;
            int dig = 11 - resto;
            if (dig == 11) dig = 0;
            if (dig == 10) dig = 9;

            return dig == (cuit[10] - '0');
        }
    }
}
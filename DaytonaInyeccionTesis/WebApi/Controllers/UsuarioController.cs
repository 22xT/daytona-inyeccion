using System.Data;
using System.Data.SqlClient;
using System.Text.RegularExpressions;
using System.Web.Http;
using WebApi.Models;
using WebApi.Filters;

namespace WebApi.Controllers
{
    [AuthorizeJwt(Roles = "Administrador")] // todo el controller solo Admin
    public class UsuarioController : ApiController
    {
        // GET: api/Usuario  (solo Administrador)
        public DataTable Get()
        {
            Usuario oUsuario = new Usuario();
            return oUsuario.ListarTodos();
        }

        // GET: api/Usuario/5  (solo Administrador)
        public DataTable Get(int id)
        {
            Usuario oUsuario = new Usuario();
            oUsuario.Id = id;
            return oUsuario.ListarPorId();
        }

        // POST: api/Usuario  (solo Administrador)
        public IHttpActionResult Post([FromBody] Usuario usuario)
        {
            string error = ValidarUsuario(usuario, true);
            if (error != "")
                return BadRequest(error);

            try
            {
                usuario.ClaveHash = BCrypt.Net.BCrypt.HashPassword(usuario.ClaveHash);
                usuario.Guardar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un usuario con ese correo.");

                return BadRequest("No se pudo guardar el usuario. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Usuario/5  (solo Administrador)
        public IHttpActionResult Put(int id, [FromBody] Usuario usuario)
        {
            string error = ValidarUsuario(usuario, false);
            if (error != "")
                return BadRequest(error);

            usuario.Id = id;

            try
            {
                if (!string.IsNullOrWhiteSpace(usuario.ClaveHash))
                    usuario.ClaveHash = BCrypt.Net.BCrypt.HashPassword(usuario.ClaveHash);
                else
                    usuario.ClaveHash = null;

                usuario.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un usuario con ese correo.");

                return BadRequest("No se pudo editar el usuario. " + ex.Message);
            }

            return Ok();
        }

        // DELETE: api/Usuario/5  (solo Administrador)
        public IHttpActionResult Delete(int id)
        {
            Usuario oUsuario = new Usuario();
            oUsuario.Id = id;

            try
            {
                oUsuario.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el usuario. " + ex.Message);
            }

            return Ok();
        }

        // PUT: api/Usuario/5/Activar  (solo Administrador)
        [HttpPut]
        [Route("api/Usuario/{id:int}/Activar")]
        public IHttpActionResult Activar(int id)
        {
            Usuario oUsuario = new Usuario();
            oUsuario.Id = id;

            try
            {
                oUsuario.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo activar el usuario. " + ex.Message);
            }

            return Ok();
        }

        [HttpPut]
        [Route("api/Usuario/{id:int}/ResetClave")]
        public IHttpActionResult ResetearClave(int id, [FromBody] Usuario usuario)
        {
            if (usuario == null)
                return BadRequest("No se recibieron datos.");

            if (string.IsNullOrWhiteSpace(usuario.ClaveHash))
                return BadRequest("La nueva contraseña es obligatoria.");

            if (usuario.ClaveHash.Length < 8)
                return BadRequest("La contraseña debe tener al menos 8 caracteres.");

            Usuario oUsuario = new Usuario();
            oUsuario.Id = id;
            oUsuario.ClaveHash = BCrypt.Net.BCrypt.HashPassword(usuario.ClaveHash);

            try
            {
                oUsuario.ResetearClave();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo resetear la contraseña. " + ex.Message);
            }

            return Ok();
        }

        private string ValidarUsuario(Usuario usuario, bool esAlta)
        {
            if (usuario == null)
                return "No se recibieron datos del usuario.";

            // Nombre: obligatorio
            if (string.IsNullOrWhiteSpace(usuario.Nombre))
                return "El nombre es obligatorio.";

            if (usuario.Nombre.Length > 100)
                return "El nombre no puede superar los 100 caracteres.";

            // Correo: obligatorio y con formato valido
            if (string.IsNullOrWhiteSpace(usuario.Correo))
                return "El correo es obligatorio.";

            if (usuario.Correo.Length > 150)
                return "El correo no puede superar los 150 caracteres.";

            if (!Regex.IsMatch(usuario.Correo, @"^[^@\s]+@[^@\s]+\.[^@\s]+$"))
                return "El correo no es válido. Debe tener el formato nombre@dominio.com";

            // Rol: obligatorio
            if (usuario.IdRol <= 0)
                return "Debe seleccionar un rol.";

            // Contraseña
            if (esAlta)
            {
                if (string.IsNullOrWhiteSpace(usuario.ClaveHash))
                    return "La contraseña es obligatoria.";

                if (usuario.ClaveHash.Length < 8)
                    return "La contraseña debe tener al menos 8 caracteres.";
            }
            else
            {
                // En edicion, solo validamos si vino una contraseña nueva.
                if (!string.IsNullOrWhiteSpace(usuario.ClaveHash) && usuario.ClaveHash.Length < 8)
                    return "La contraseña debe tener al menos 8 caracteres.";
            }

            return "";
        }

    }
}


using System;
using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Models;

namespace WebApi.Controllers
{
    public class LoginController : ApiController
    {
        // La conexion sale de Web.config (en Azure, de la configuracion del App Service),
        // igual que en el resto de los modelos. Antes estaba escrita aca y en Azure
        // el login buscaba el SQL Server de la PC de desarrollo.
        private string connectionstring = Config.Conexion;

        // POST: api/Usuario/Login
        [HttpPost]
        [AllowAnonymous]
        [Route("api/Usuario/Login")]
        public IHttpActionResult Login([FromBody] LoginRequest req)
        {
            // Validaciones basicas
            if (req == null)
                return BadRequest("No se recibieron datos.");

            if (string.IsNullOrWhiteSpace(req.Correo))
                return BadRequest("El correo es obligatorio.");

            if (string.IsNullOrWhiteSpace(req.Clave))
                return BadRequest("La contraseña es obligatoria.");

            // Buscar usuario por correo
            DataTable dt = new DataTable();

            try
            {
                string sqlSentencia = "SP_Usuario_GetByCorreo";
                SqlConnection sqlCnn = new SqlConnection(connectionstring);
                SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

                sqlCom.CommandType = CommandType.StoredProcedure;
                sqlCom.Parameters.Add("@Correo", SqlDbType.NVarChar).Value = req.Correo;

                SqlDataAdapter da = new SqlDataAdapter();
                da.SelectCommand = sqlCom;

                DataSet ds = new DataSet();
                sqlCnn.Open();
                da.Fill(ds);
                sqlCnn.Close();

                dt = ds.Tables[0];
            }
            catch (SqlException ex)
            {
                return BadRequest("Error al consultar el usuario. " + ex.Message);
            }

            // Usuario no encontrado
            if (dt.Rows.Count == 0)
                return BadRequest("Correo o contraseña incorrectos.");

            DataRow row = dt.Rows[0];

            // Verificar que este activo
            bool activo = Convert.ToBoolean(row["Activo"]);
            if (!activo)
                return BadRequest("El usuario está dado de baja.");

            // Verificar contraseña con BCrypt
            string claveHash = row["ClaveHash"].ToString();
            bool claveValida = BCrypt.Net.BCrypt.Verify(req.Clave, claveHash);

            if (!claveValida)
                return BadRequest("Correo o contraseña incorrectos.");

            // Login OK: generar token
            int id = Convert.ToInt32(row["Id"]);
            string nombre = row["Nombre"].ToString();
            string correo = row["Correo"].ToString();
            string rol = row["Rol"].ToString();

            string token = JwtHelper.GenerarToken(id, nombre, correo, rol);

            // Registrar ultimo acceso
            try
            {
                Usuario u = new Usuario();
                u.Id = id;
                u.RegistrarAcceso();
            }
            catch (SqlException) { }

            // Armar respuesta
            LoginResponse resp = new LoginResponse();
            resp.Ok = true;
            resp.Token = token;
            resp.Id = id;
            resp.Nombre = nombre;
            resp.Correo = correo;
            resp.Rol = rol;
            resp.Mensaje = "Bienvenido.";

            return Ok(resp);
        }
    }
}
namespace WebApi.Models
{
    /// <summary>
    /// DTO que recibe el endpoint POST /api/Usuario/Login.
    /// </summary>
    public class LoginRequest
    {
        public string Correo { get; set; }
        public string Clave { get; set; }
    }
}

namespace WebApi.Models
{
    /// <summary>
    /// DTO que devuelve el endpoint POST /api/Usuario/Login al frontend.
    /// </summary>
    public class LoginResponse
    {
        public bool Ok { get; set; }
        public string Token { get; set; }
        public int Id { get; set; }
        public string Nombre { get; set; }
        public string Correo { get; set; }
        public string Rol { get; set; }
        public string Mensaje { get; set; }
    }
}

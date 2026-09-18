using System;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace WebApi.Models
{
    /// <summary>
    /// Helper para generar y validar tokens JWT.
    /// La configuracion sale de Config, que la lee del Web.config y en
    /// Azure la toma de la configuracion del App Service.
    /// </summary>
    public static class JwtHelper
    {
        /* Antes estos valores se leian con ConfigurationManager directo
           y ExpirationHours usaba int.Parse con "?? 8". Ese operador solo
           cubre el caso NULL: si la clave trae "ocho" o queda vacia con
           espacios, Parse lanza excepcion al inicializar la clase y la
           aplicacion no arranca, con un mensaje que no dice cual fue el
           problema. Config usa TryParse y cae a 8. */

        private static readonly string SecretKey = Config.JwtSecretKey;
        private static readonly string Issuer = Config.JwtIssuer;
        private static readonly string Audience = Config.JwtAudience;
        private static readonly int ExpirationHours = Config.JwtExpirationHours;

        /// <summary>
        /// Genera un JWT firmado con los claims del usuario.
        /// </summary>
        public static string GenerarToken(int userId, string nombre, string correo, string rol)
        {
            // Sin clave no se puede firmar. Conviene que falle con un
            // mensaje claro y no con un NullReference adentro de la libreria.
            if (string.IsNullOrWhiteSpace(SecretKey))
                throw new InvalidOperationException(
                    "Falta la clave 'Jwt:SecretKey' en la configuración.");

            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SecretKey));
            var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var claims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
                new Claim(JwtRegisteredClaimNames.Email, correo ?? ""),
                new Claim("nombre", nombre ?? ""),
                new Claim(ClaimTypes.Role, rol ?? ""),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
            };

            var token = new JwtSecurityToken(
                issuer: Issuer,
                audience: Audience,
                claims: claims,
                notBefore: DateTime.UtcNow,
                expires: DateTime.UtcNow.AddHours(ExpirationHours),
                signingCredentials: credentials
            );

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        /// <summary>
        /// Valida un token y devuelve los claims si es valido. Si no, devuelve null.
        /// </summary>
        public static ClaimsPrincipal ValidarToken(string token)
        {
            if (string.IsNullOrWhiteSpace(token))
                return null;

            if (string.IsNullOrWhiteSpace(SecretKey))
                return null;

            try
            {
                var handler = new JwtSecurityTokenHandler();
                var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SecretKey));

                var validationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = Issuer,
                    ValidateAudience = true,
                    ValidAudience = Audience,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = key,
                    ClockSkew = TimeSpan.FromMinutes(1)
                };

                SecurityToken validatedToken;
                var principal = handler.ValidateToken(token, validationParameters, out validatedToken);
                return principal;
            }
            catch
            {
                // Token invalido, expirado, mal firmado, etc.
                return null;
            }
        }
    }
}
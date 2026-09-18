using System;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Claims;
using System.Web.Http;
using System.Web.Http.Controllers;
using System.Web.Http.Filters;
using WebApi.Models;

namespace WebApi.Filters
{
    /// <summary>
    /// Filtro de autorizacion basado en JWT.
    /// 
    /// Uso:
    ///   [AuthorizeJwt]                              -> cualquier usuario logueado
    ///   [AuthorizeJwt(Roles = "Administrador")]     -> solo Administrador
    ///   [AuthorizeJwt(Roles = "Administrador,Invitado")] -> ambos roles
    /// 
    /// Si no hay token o el token es invalido -> 401 Unauthorized.
    /// Si el token es valido pero el rol no coincide -> 403 Forbidden.
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
    public class AuthorizeJwtAttribute : AuthorizationFilterAttribute
    {
        public string Roles { get; set; }

        public override void OnAuthorization(HttpActionContext actionContext)
        {
            // 1. Si la accion tiene [AllowAnonymous], dejarla pasar.
            if (SkipAuthorization(actionContext)) return;

            // 2. Extraer el token del header Authorization: "Bearer xxxx"
            var authHeader = actionContext.Request.Headers.Authorization;
            if (authHeader == null || authHeader.Scheme != "Bearer" ||
                string.IsNullOrWhiteSpace(authHeader.Parameter))
            {
                actionContext.Response = actionContext.Request.CreateErrorResponse(
                    HttpStatusCode.Unauthorized, "Token faltante.");
                return;
            }

            // 3. Validar el token
            var principal = JwtHelper.ValidarToken(authHeader.Parameter);
            if (principal == null)
            {
                actionContext.Response = actionContext.Request.CreateErrorResponse(
                    HttpStatusCode.Unauthorized, "Token invalido o expirado.");
                return;
            }

            // 4. Si hay restriccion de rol, validarla
            if (!string.IsNullOrWhiteSpace(Roles))
            {
                var rolesPermitidos = Roles.Split(',')
                    .Select(r => r.Trim())
                    .Where(r => !string.IsNullOrEmpty(r))
                    .ToArray();

                var rolUsuario = principal.FindFirst(ClaimTypes.Role)?.Value;

                if (string.IsNullOrEmpty(rolUsuario) ||
                    !rolesPermitidos.Contains(rolUsuario, StringComparer.OrdinalIgnoreCase))
                {
                    actionContext.Response = actionContext.Request.CreateErrorResponse(
                        HttpStatusCode.Forbidden,
                        "No tiene permisos para acceder a este recurso.");
                    return;
                }
            }

            // 5. Adjuntar el principal al request para que los Controllers puedan leer User.Identity
            System.Threading.Thread.CurrentPrincipal = principal;
            if (System.Web.HttpContext.Current != null)
                System.Web.HttpContext.Current.User = principal;
        }

        private static bool SkipAuthorization(HttpActionContext actionContext)
        {
            return actionContext.ActionDescriptor.GetCustomAttributes<AllowAnonymousAttribute>().Any()
                || actionContext.ControllerContext.ControllerDescriptor
                    .GetCustomAttributes<AllowAnonymousAttribute>().Any();
        }
    }
}

using System;
using System.Data;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    /* Auditoria general (script 83). Solo Dueño y Administrador.
       Sin fechas: los ultimos 30 dias. */
    [AuthorizeJwt(Roles = "Dueño,Administrador")]
    public class AuditoriaController : ApiController
    {
        // GET api/Auditoria?desde=2026-10-01&hasta=2026-10-26&idUsuario=3&tipo=Precios&texto=bujia&max=500
        [HttpGet, Route("api/Auditoria")]
        public DataSet Get(DateTime? desde = null, DateTime? hasta = null, int? idUsuario = null,
                           string tipo = null, string texto = null, int max = 500)
        {
            DateTime h = hasta ?? DateTime.Today;
            DateTime d = desde ?? h.AddDays(-30);
            if (h < d) h = d;
            return new Auditoria().Listar(d, h, idUsuario, tipo, texto, max);
        }
    }
}

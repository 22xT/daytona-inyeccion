using System.Data;
using System.Data.SqlClient;
using System.Web.Http;
using WebApi.Filters;
using WebApi.Models;

namespace WebApi.Controllers
{
    [AuthorizeJwt]
    public class RepuestoController : ApiController
    {
        // GET: api/Repuesto  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get()
        {
            Repuesto oRepuesto = new Repuesto();
            return oRepuesto.ListarTodos();
        }

        // GET: api/Repuesto/5  (todos los roles autenticados)
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable Get(int id)
        {
            Repuesto oRepuesto = new Repuesto();
            oRepuesto.Id = id;
            return oRepuesto.ListarPorId();
        }

        // POST: api/Repuesto  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Post([FromBody] Repuesto repuesto)
        {
            string error = ValidarRepuesto(repuesto);
            if (error != "")
                return BadRequest(error);

            try
            {
                repuesto.Guardar();
                // Se devuelven Id y Codigo para dejar seleccionado el repuesto nuevo
                return Ok(new { Id = repuesto.Id, Codigo = repuesto.Codigo });
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000)
                    return BadRequest(ex.Message);

                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un repuesto con esa descripción o ese código.");

                return BadRequest("No se pudo guardar el repuesto.");
            }
        }

        // PUT: api/Repuesto/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Put(int id, [FromBody] Repuesto repuesto)
        {
            string error = ValidarRepuesto(repuesto);
            if (error != "")
                return BadRequest(error);

            repuesto.Id = id;

            try
            {
                repuesto.Editar();
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000)
                    return BadRequest(ex.Message);

                if (ex.Number == 2627 || ex.Number == 2601)
                    return BadRequest("Ya existe un repuesto con esa descripción o ese código.");

                return BadRequest("No se pudo editar el repuesto.");
            }

            return Ok();
        }

        // DELETE: api/Repuesto/5  (Administrador y Analista)
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Delete(int id)
        {
            Repuesto oRepuesto = new Repuesto();
            oRepuesto.Id = id;

            try
            {
                oRepuesto.Eliminar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo dar de baja el repuesto. " + ex.Message);
            }

            return Ok();
        }

        // GET: api/Repuesto/Filtrar?IdRubro=1&IdMarca=2  (los que pueden vender o pedir)
        [HttpGet]
        [Route("api/Repuesto/Filtrar")]
        [AuthorizeJwt(Roles = "Administrador,Supervisor,Vendedor,Analista,Sistema")]
        public DataTable GetByFiltro(int IdRubro, int IdMarca)
        {
            Repuesto oRepuesto = new Repuesto();
            oRepuesto.IdRubro = IdRubro;
            oRepuesto.IdMarca = IdMarca;
            return oRepuesto.ListarPorFiltro();
        }

        // GET: api/Repuesto/PrecioSugerido           (todo el catalogo)
        // GET: api/Repuesto/PrecioSugerido?idRepuesto=5  (uno solo)
        // Solo propone: no modifica ningun precio.
        [HttpGet]
        [Route("api/Repuesto/PrecioSugerido")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public DataTable PrecioSugerido(int idRepuesto = 0)
        {
            Repuesto oRepuesto = new Repuesto();
            return oRepuesto.PrecioSugerido(idRepuesto);
        }

        // PUT: api/Repuesto/5/AplicarPrecio
        // Recibe el precio NETO. El final lo calcula el procedimiento.
        [HttpPut]
        [Route("api/Repuesto/{id:int}/AplicarPrecio")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Analista")]
        public IHttpActionResult AplicarPrecio(int id, [FromBody] Repuesto repuesto)
        {
            if (repuesto == null || !repuesto.PrecioNetoVenta.HasValue || repuesto.PrecioNetoVenta.Value <= 0)
                return BadRequest("Debe indicarse el precio neto de venta.");

            if (repuesto.PrecioNetoVenta.Value > 10000000)
                return BadRequest("El precio neto no puede superar los $10.000.000.");

            repuesto.Id = id;

            try
            {
                repuesto.AplicarPrecio();
                return Ok();
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest("No se pudo aplicar el precio.");
            }
        }

        // POST: api/Repuesto/IncorporarDesdeLista
        // Da de alta un repuesto a partir de un articulo de la lista de un proveedor.
        [HttpPost]
        [Route("api/Repuesto/IncorporarDesdeLista")]
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult IncorporarDesdeLista([FromBody] Repuesto repuesto)
        {
            if (repuesto == null || repuesto.IdListaProveedor <= 0)
                return BadRequest("Debe indicarse el artículo de la lista del proveedor.");

            try
            {
                repuesto.IncorporarDesdeLista();
                return Ok(new { Id = repuesto.Id, Codigo = repuesto.Codigo });
            }
            catch (SqlException ex)
            {
                if (ex.Number >= 50000) return BadRequest(ex.Message);
                return BadRequest("No se pudo incorporar el repuesto.");
            }
        }

        // GET: api/Repuesto/5/OtrosProveedores
        // Candidatos a ser el mismo repuesto en otras listas.
        [HttpGet]
        [Route("api/Repuesto/{id:int}/OtrosProveedores")]
        [AuthorizeJwt(Roles = "Dueño,Administrador,Supervisor,Analista")]
        public DataTable OtrosProveedores(int id)
        {
            Repuesto oRepuesto = new Repuesto();
            oRepuesto.Id = id;
            return oRepuesto.BuscarEnOtrosProveedores();
        }

        // PUT: api/Repuesto/5/Activar  (Administrador y Analista)
        [HttpPut]
        [Route("api/Repuesto/{id:int}/Activar")]
        [AuthorizeJwt(Roles = "Administrador,Analista")]
        public IHttpActionResult Activar(int id)
        {
            Repuesto oRepuesto = new Repuesto();
            oRepuesto.Id = id;

            try
            {
                oRepuesto.Activar();
            }
            catch (SqlException ex)
            {
                return BadRequest("No se pudo reactivar el repuesto. " + ex.Message);
            }

            return Ok();
        }

        // Valida los datos del repuesto. Devuelve "" si esta todo bien.
        private string ValidarRepuesto(Repuesto repuesto)
        {
            if (repuesto == null)
                return "No se recibieron datos del repuesto.";

            if (string.IsNullOrWhiteSpace(repuesto.Descripcion))
                return "La descripción es obligatoria.";

            if (repuesto.Descripcion.Trim().Length < 2)
                return "La descripción es demasiado corta.";

            /* El precio puede llegar de tres formas, segun la pantalla:
               - PrecioNetoVenta: el precio sin IVA, que es la forma correcta
               - PrecioCompra: el costo, y el sistema calcula el precio con el margen
               - PrecioDeVenta: el precio final con IVA, que usa el formulario viejo
               Alcanza con que venga UNA de las tres. */
            bool tieneNeto   = repuesto.PrecioNetoVenta.HasValue && repuesto.PrecioNetoVenta.Value > 0;
            bool tieneCosto  = repuesto.PrecioCompra.HasValue && repuesto.PrecioCompra.Value > 0;
            bool tieneFinal  = repuesto.PrecioDeVenta > 0;

            if (!tieneNeto && !tieneCosto && !tieneFinal)
                return "Debe indicarse el precio de venta o el costo de compra.";

            if (tieneFinal && repuesto.PrecioDeVenta > 10000000)
                return "El precio de venta no puede superar los $10.000.000. Verificá el monto.";

            if (tieneNeto && repuesto.PrecioNetoVenta.Value > 10000000)
                return "El precio neto no puede superar los $10.000.000. Verificá el monto.";

            if (tieneCosto && repuesto.PrecioCompra.Value > 10000000)
                return "El costo de compra no puede superar los $10.000.000. Verificá el monto.";

            if (!string.IsNullOrWhiteSpace(repuesto.Codigo) && repuesto.Codigo.Length > 40)
                return "El código no puede superar los 40 caracteres.";

            if (!string.IsNullOrWhiteSpace(repuesto.CodigoFabricante) && repuesto.CodigoFabricante.Length > 40)
                return "El código de fabricante no puede superar los 40 caracteres.";

            // El modelo es OPCIONAL: los repuestos universales (abrazaderas, aceites)
            // no corresponden a una marca/modelo. Si viene, debe ser válido.
            if (repuesto.IdModelo.HasValue && repuesto.IdModelo.Value <= 0)
                return "El modelo indicado no es válido.";

            if (repuesto.IdRubro <= 0)
                return "Debe seleccionar un rubro.";

            return "";
        }
    }
}
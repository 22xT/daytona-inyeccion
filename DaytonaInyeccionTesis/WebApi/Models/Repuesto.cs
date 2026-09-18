using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Repuesto
    {
        // La cadena vive en Web.config, no en el codigo.
        // En Azure se reemplaza desde la configuracion del App Service.
        private string connectionstring = Config.Conexion;
        public bool Activo { get; set; }
        public string Codigo { get; set; }
        public int Id { get; set; }
        public string Descripcion { get; set; }
        public decimal PrecioDeVenta { get; set; }
        public int? IdModelo { get; set; }   // nullable: los repuestos universales no tienen modelo
        public int IdRubro { get; set; }

        // No persiste en BD; se usa solo como parametro del filtro (SP_Repuesto_Filtrar).
        public int IdMarca { get; set; }

        /* ---------- Modelo de precios ---------- */

        // Costo real de compra, ya con los descuentos del proveedor aplicados
        public decimal? PrecioCompra { get; set; }

        // Precio de venta SIN IVA. El precio final se calcula, nunca se guarda suelto.
        public decimal? PrecioNetoVenta { get; set; }

        public int? IdAlicuotaIva { get; set; }

        // Margen propio: pisa al del rubro cuando esta cargado
        public decimal? MargenPropio { get; set; }

        public DateTime? FechaUltimaCompra { get; set; }

        /* ---------- Identidad del fabricante ---------- */

        // Codigo del fabricante (A0254 de Perfecto, AC25085 de Nakata).
        // Es la mejor señal para reconocer la misma pieza entre proveedores.
        public string CodigoFabricante { get; set; }

        // OJO: no es lo mismo que Marca. Marca es la marca del AUTO (Fiat, Peugeot);
        // esta es la del fabricante del repuesto (Perfecto, Nakata, Fispa).
        public string MarcaFabricante { get; set; }

        public int? StockMinimo { get; set; }

        // Solo para incorporar desde la lista de un proveedor
        public int IdListaProveedor { get; set; }

        // Listar todos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Repuesto_GetAll";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Listar uno por Id
        public DataTable ListarPorId()
        {
            string sqlSentencia = "SP_Repuesto_GetId";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Insertar. Devuelve el Id generado y completa la propiedad Codigo,
        // que puede venir del proveedor o generarse como R-000001.
        public int Guardar()
        {
            string sqlSentencia = "SP_Repuesto_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Descripcion", SqlDbType.NVarChar).Value = (object)Descripcion ?? DBNull.Value;
            sqlCom.Parameters.Add("@PrecioDeVenta", SqlDbType.Decimal).Value =
                PrecioDeVenta > 0 ? (object)PrecioDeVenta : DBNull.Value;
            sqlCom.Parameters.Add("@IdModelo", SqlDbType.Int).Value = (object)IdModelo ?? DBNull.Value;
            sqlCom.Parameters.Add("@IdRubro", SqlDbType.Int).Value = IdRubro;

            sqlCom.Parameters.Add("@Codigo", SqlDbType.VarChar, 40).Value =
                string.IsNullOrEmpty(Codigo) ? (object)DBNull.Value : Codigo;
            sqlCom.Parameters.Add("@CodigoFabricante", SqlDbType.VarChar, 40).Value =
                string.IsNullOrEmpty(CodigoFabricante) ? (object)DBNull.Value : CodigoFabricante;
            sqlCom.Parameters.Add("@MarcaFabricante", SqlDbType.VarChar, 60).Value =
                string.IsNullOrEmpty(MarcaFabricante) ? (object)DBNull.Value : MarcaFabricante;
            sqlCom.Parameters.Add("@PrecioCompra", SqlDbType.Decimal).Value =
                PrecioCompra.HasValue ? (object)PrecioCompra.Value : DBNull.Value;
            sqlCom.Parameters.Add("@PrecioNetoVenta", SqlDbType.Decimal).Value =
                PrecioNetoVenta.HasValue ? (object)PrecioNetoVenta.Value : DBNull.Value;
            sqlCom.Parameters.Add("@IdAlicuotaIva", SqlDbType.Int).Value =
                IdAlicuotaIva.HasValue ? (object)IdAlicuotaIva.Value : DBNull.Value;
            sqlCom.Parameters.Add("@StockMinimo", SqlDbType.Int).Value =
                StockMinimo.HasValue ? (object)StockMinimo.Value : 5;

            sqlCnn.Open();
            SqlDataReader dr = sqlCom.ExecuteReader();
            if (dr.Read())
            {
                Id = Convert.ToInt32(dr["Id"]);
                Codigo = Convert.ToString(dr["Codigo"]);
            }
            dr.Close();
            sqlCnn.Close();

            return Id;
        }

        // Actualizar
        public void Editar()
        {
            string sqlSentencia = "SP_Repuesto_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Descripcion", SqlDbType.NVarChar).Value = (object)Descripcion ?? DBNull.Value;
            sqlCom.Parameters.Add("@PrecioDeVenta", SqlDbType.Decimal).Value =
                PrecioDeVenta > 0 ? (object)PrecioDeVenta : DBNull.Value;
            sqlCom.Parameters.Add("@IdModelo", SqlDbType.Int).Value = (object)IdModelo ?? DBNull.Value;
            sqlCom.Parameters.Add("@IdRubro", SqlDbType.Int).Value = IdRubro;

            sqlCom.Parameters.Add("@Codigo", SqlDbType.VarChar, 40).Value =
                string.IsNullOrEmpty(Codigo) ? (object)DBNull.Value : Codigo;
            sqlCom.Parameters.Add("@CodigoFabricante", SqlDbType.VarChar, 40).Value =
                string.IsNullOrEmpty(CodigoFabricante) ? (object)DBNull.Value : CodigoFabricante;
            sqlCom.Parameters.Add("@MarcaFabricante", SqlDbType.VarChar, 60).Value =
                string.IsNullOrEmpty(MarcaFabricante) ? (object)DBNull.Value : MarcaFabricante;
            sqlCom.Parameters.Add("@PrecioCompra", SqlDbType.Decimal).Value =
                PrecioCompra.HasValue ? (object)PrecioCompra.Value : DBNull.Value;
            sqlCom.Parameters.Add("@PrecioNetoVenta", SqlDbType.Decimal).Value =
                PrecioNetoVenta.HasValue ? (object)PrecioNetoVenta.Value : DBNull.Value;
            sqlCom.Parameters.Add("@IdAlicuotaIva", SqlDbType.Int).Value =
                IdAlicuotaIva.HasValue ? (object)IdAlicuotaIva.Value : DBNull.Value;
            // 0 = lo que no viene se conserva. Evita que editar la descripcion
            // desde el formulario viejo borre el costo cargado por otra pantalla.
            sqlCom.Parameters.Add("@PisarNulos", SqlDbType.Bit).Value = false;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Eliminar
        public void Eliminar()
        {
            string sqlSentencia = "SP_Repuesto_D";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Listar por filtro de rubro y marca
        public DataTable ListarPorFiltro()
        {
            string sqlSentencia = "SP_Repuesto_Filtrar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRubro", SqlDbType.Int).Value = IdRubro;
            sqlCom.Parameters.Add("@IdMarca", SqlDbType.Int).Value = IdMarca;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }
        /* ---------- Precios ---------- */

        // Propuesta de precio a partir del costo y el margen. NO modifica nada.
        // Si IdRepuesto es 0, devuelve la propuesta para todo el catalogo.
        public DataTable PrecioSugerido(int idRepuesto)
        {
            string sqlSentencia = "SP_Repuesto_PrecioSugerido";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value =
                idRepuesto > 0 ? (object)idRepuesto : DBNull.Value;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Aplica el precio confirmado. Recibe el NETO: el final lo calcula el SP.
        public void AplicarPrecio()
        {
            string sqlSentencia = "SP_Repuesto_AplicarPrecio";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@PrecioNetoVenta", SqlDbType.Decimal).Value =
                PrecioNetoVenta.HasValue ? (object)PrecioNetoVenta.Value : DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Alta a partir de un articulo de la lista de un proveedor.
        // Toma codigo, descripcion, rubro y costo de la lista, calcula el precio
        // con el margen y deja enlazada la fila de la lista con el repuesto nuevo.
        public int IncorporarDesdeLista()
        {
            string sqlSentencia = "SP_Repuesto_IncorporarDesdeLista";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdListaProveedor", SqlDbType.Int).Value = IdListaProveedor;
            // El rubro lo elige el usuario: los del proveedor no siempre
            // se corresponden con los propios.
            sqlCom.Parameters.Add("@IdRubro", SqlDbType.Int).Value =
                IdRubro > 0 ? (object)IdRubro : DBNull.Value;
            sqlCom.Parameters.Add("@IdModelo", SqlDbType.Int).Value = (object)IdModelo ?? DBNull.Value;
            sqlCom.Parameters.Add("@StockMinimo", SqlDbType.Int).Value =
                StockMinimo.HasValue ? (object)StockMinimo.Value : 5;
            sqlCom.Parameters.Add("@PrecioNetoVenta", SqlDbType.Decimal).Value =
                PrecioNetoVenta.HasValue ? (object)PrecioNetoVenta.Value : DBNull.Value;

            sqlCnn.Open();
            SqlDataReader dr = sqlCom.ExecuteReader();
            if (dr.Read())
            {
                Id = Convert.ToInt32(dr["Id"]);
                Codigo = Convert.ToString(dr["Codigo"]);
            }
            dr.Close();
            sqlCnn.Close();

            return Id;
        }

        // Candidatos a ser el mismo repuesto en otros proveedores.
        // Solo sugiere: el enlace lo confirma una persona.
        public DataTable BuscarEnOtrosProveedores()
        {
            string sqlSentencia = "SP_Repuesto_BuscarEnOtrosProveedores";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = Id;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Reactivar repuesto descontinuado
        public void Activar()
        {
            string sqlSentencia = "SP_Repuesto_Activar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }

}

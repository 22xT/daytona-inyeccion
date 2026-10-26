using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    // Tablero de decisiones (script 81). Cada area devuelve varias tablas
    // con nombre, para que el JSON se lea solo.
    public class Tablero
    {
        private string connectionstring = Config.Conexion;

        public DataSet Resumen(DateTime? desde, DateTime? hasta)
        {
            return Ejecutar("SP_Tablero_Resumen", desde, hasta, null,
                "Numeros", "Titulares", "Alertas");
        }

        public DataSet Ventas(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Tablero_Ventas", desde, hasta, null,
                "Mensual", "DiaSemana", "Hora", "MediosPago", "TipoCliente", "Vendedores", "Comparacion");
        }

        public DataSet Productos(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Tablero_Productos", desde, hasta, null,
                "Ranking", "Rubros", "Marcas", "Temporada", "Historia", "Abc", "Tendencia");
        }

        public DataSet Producto(int idRepuesto)
        {
            return Ejecutar("SP_Tablero_Producto", null, null, idRepuesto,
                "Ficha", "Mensual", "Compras");
        }

        public DataSet Proveedores(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Tablero_Proveedores", desde, hasta, null,
                "Proveedores", "Llegadas", "Precios", "Problemas", "ComprasMensuales");
        }

        public DataSet Clientes(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Tablero_Clientes", desde, hasta, null,
                "Resumen", "Mejores", "Perdidos", "Deudores", "Encargos", "Frecuencia");
        }

        public DataSet Stock()
        {
            return Ejecutar("SP_Tablero_Stock", null, null, null,
                "Resumen", "Quiebres", "Inmovilizado", "Cobertura", "Rubros");
        }

        public DataSet Rentabilidad(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Tablero_Rentabilidad", desde, hasta, null,
                "Mensual", "Gastos", "Totales");
        }

        private DataSet Ejecutar(string sp, DateTime? desde, DateTime? hasta, int? idRepuesto, params string[] nombres)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 90;
                if (idRepuesto.HasValue)
                    cmd.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = idRepuesto.Value;
                else if (sp != "SP_Tablero_Stock")
                {
                    cmd.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value.Date : DBNull.Value;
                    cmd.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value.Date : DBNull.Value;
                }

                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    cnn.Open();
                    da.Fill(ds);
                }
                for (int i = 0; i < ds.Tables.Count && i < nombres.Length; i++)
                    ds.Tables[i].TableName = nombres[i];
                return ds;
            }
        }
    }
}

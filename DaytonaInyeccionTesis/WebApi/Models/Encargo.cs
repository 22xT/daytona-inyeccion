using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Encargos: el cliente pide algo que no hay en stock, opcionalmente
       deja una seña, se le avisa cuando llega y se entrega con una venta. */

    public class EncargoLinea
    {
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public decimal PrecioPactado { get; set; }
    }

    public class EncargoDto
    {
        public int? IdCliente { get; set; }
        public string Nombre { get; set; }
        public string Telefono { get; set; }
        public string Observacion { get; set; }
        public List<EncargoLinea> Lineas { get; set; }
        public int? IdMedioSena { get; set; }
        public decimal? MontoSena { get; set; }
        // Si viene, el encargo se suma al pedido en armado de ese proveedor
        public int? IdProveedorPedido { get; set; }
    }

    public class EncargoSenaDto
    {
        public int IdMedioPago { get; set; }
        public decimal Monto { get; set; }
    }

    public class EncargoCancelarDto
    {
        public string Motivo { get; set; }
        public string Resolucion { get; set; }          // DEVUELTA | A_FAVOR | RETENIDA
        public int? IdCuentaDevolucion { get; set; }
    }

    public class Encargo
    {
        private string connectionstring = Config.Conexion;
        private static object N(object v) { return v ?? DBNull.Value; }

        public DataSet Listar(bool abiertos)
        {
            return Consultar("SP_Encargo_GetAll", c => c.Parameters.Add("@Abiertos", SqlDbType.Bit).Value = abiertos);
        }

        public DataSet Obtener(int id)
        {
            return Consultar("SP_Encargo_Get", c => c.Parameters.Add("@Id", SqlDbType.Int).Value = id);
        }

        public DataRow Crear(EncargoDto d, int idUsuario)
        {
            DataTable t = new DataTable();
            t.Columns.Add("IdRepuesto", typeof(int));
            t.Columns.Add("Cantidad", typeof(int));
            t.Columns.Add("PrecioPactado", typeof(decimal));
            if (d.Lineas != null)
                foreach (EncargoLinea l in d.Lineas) t.Rows.Add(l.IdRepuesto, l.Cantidad, l.PrecioPactado);

            DataSet ds = Consultar("SP_Encargo_I", c =>
            {
                c.Parameters.Add("@IdCliente", SqlDbType.Int).Value = N(d.IdCliente);
                c.Parameters.Add("@Nombre", SqlDbType.NVarChar, 80).Value = N(d.Nombre);
                c.Parameters.Add("@Telefono", SqlDbType.NVarChar, 30).Value = N(d.Telefono);
                c.Parameters.Add("@Observacion", SqlDbType.NVarChar, 250).Value = N(d.Observacion);
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", t);
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.EncargoLineaType";
                c.Parameters.Add("@IdMedioSena", SqlDbType.Int).Value = N(d.IdMedioSena);
                c.Parameters.Add("@MontoSena", SqlDbType.Decimal).Value = N(d.MontoSena);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                c.Parameters.Add("@IdProveedorPedido", SqlDbType.Int).Value = N(d.IdProveedorPedido);
            });
            return ds.Tables[0].Rows[0];
        }

        public void AgregarSena(int id, EncargoSenaDto d, int idUsuario)
        {
            Consultar("SP_Encargo_AgregarSena", c =>
            {
                c.Parameters.Add("@IdEncargo", SqlDbType.Int).Value = id;
                c.Parameters.Add("@IdMedioPago", SqlDbType.Int).Value = d.IdMedioPago;
                c.Parameters.Add("@Monto", SqlDbType.Decimal).Value = d.Monto;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        // Encargos que se pueden separar con lo que trajo un pedido
        public DataTable ParaSeparar(int idPedido)
        {
            return Consultar("SP_Encargo_ParaSeparar", c => c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido).Tables[0];
        }

        // Cuanto hay reservado de cada repuesto por encargos abiertos
        public DataTable Reservas()
        {
            return Consultar("SP_Stock_Reservas", c => { }).Tables[0];
        }

        public void MarcarAvisado(int id)
        {
            Consultar("SP_Encargo_MarcarAvisado", c => c.Parameters.Add("@Id", SqlDbType.Int).Value = id);
        }

        public void Cancelar(int id, EncargoCancelarDto d, int idUsuario)
        {
            Consultar("SP_Encargo_Cancelar", c =>
            {
                c.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(d.Motivo);
                c.Parameters.Add("@Resolucion", SqlDbType.VarChar, 10).Value = N(d.Resolucion);
                c.Parameters.Add("@IdCuentaDevolucion", SqlDbType.Int).Value = N(d.IdCuentaDevolucion);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        private DataSet Consultar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd)) { da.Fill(ds); }
                return ds;
            }
        }
    }
}

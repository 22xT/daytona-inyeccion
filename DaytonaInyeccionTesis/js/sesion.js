
function verificarSesion() {
  const usuario = JSON.parse(localStorage.getItem("usuario"));

  if (!usuario) {
    Swal.fire({
      icon: "warning",
      title: "Sesión expirada o no iniciada",
      text: "Por favor, inicie sesión para continuar.",
      confirmButtonText: "Ir al login"
    }).then(() => {
      window.location.href = "Login.html";
    });
    return false;
  }

  
  const userInfo = document.getElementById("user-info");
  if (userInfo) {
    userInfo.innerHTML = `
      <strong>${usuario.Nombre}</strong> 
      <span class="badge bg-secondary">${usuario.Rol}</span>
    `;
  }

  return true;
}


function cerrarSesion() {
  Swal.fire({
    title: "¿Cerrar sesión?",
    text: "Se cerrará tu sesión actual.",
    icon: "question",
    showCancelButton: true,
    confirmButtonColor: "#d33",
    cancelButtonColor: "#3085d6",
    confirmButtonText: "Sí, salir"
  }).then((result) => {
    if (result.isConfirmed) {
      localStorage.removeItem("usuario");
      window.location.href = "Login.html";
    }
  });
}

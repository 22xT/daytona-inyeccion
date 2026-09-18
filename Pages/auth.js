
(function (global) {
  'use strict';

  function getUsuario() {
    try { return JSON.parse(localStorage.getItem('usuario')); }
    catch (e) { return null; }
  }

  function getToken() {
    return localStorage.getItem('token');
  }

  function logout() {
    localStorage.removeItem('usuario');
    localStorage.removeItem('token');
    window.location.href = 'Login.html';
  }

  function requireSession() {
    if (!getToken() || !getUsuario()) {
      window.location.href = 'Login.html';
      return false;
    }
    return true;
  }

  function requireRole(rol) {
    var u = getUsuario();
    if (!u || u.Rol !== rol) {
      if (typeof Swal !== 'undefined') {
        Swal.fire({
          icon: 'error',
          title: 'Acceso denegado',
          text: 'No tiene permisos para acceder a esta seccion.'
        }).then(function () { window.location.href = 'index.html'; });
      } else {
        alert('Acceso denegado.');
        window.location.href = 'index.html';
      }
      return false;
    }
    return true;
  }

  function fetchAuth(url, options) {
    options = options || {};
    options.headers = options.headers || {};

    var token = getToken();
    if (token) {
      options.headers['Authorization'] = 'Bearer ' + token;
    }

    if (options.body && !options.headers['Content-Type']) {
      options.headers['Content-Type'] = 'application/json';
    }

    return fetch(url, options).then(function (response) {
      if (response.status === 401) {
        // Token expirado o invalido
        if (typeof Swal !== 'undefined') {
          Swal.fire({
            icon: 'warning',
            title: 'Sesion expirada',
            text: 'Por favor, vuelva a iniciar sesion.',
            confirmButtonText: 'Aceptar'
          }).then(logout);
        } else {
          alert('Sesion expirada. Vuelva a iniciar sesion.');
          logout();
        }
        // Devolvemos una promesa rechazada para que el caller no continue
        return Promise.reject(new Error('401 Unauthorized'));
      }
      if (response.status === 403) {
        if (typeof Swal !== 'undefined') {
          Swal.fire({
            icon: 'error',
            title: 'Sin permisos',
            text: 'No tiene permisos para realizar esta accion.'
          });
        }
        return Promise.reject(new Error('403 Forbidden'));
      }
      return response;
    });
  }

  // Exportar al global
  global.Auth = {
    getUsuario: getUsuario,
    getToken: getToken,
    logout: logout,
    requireSession: requireSession,
    requireRole: requireRole,
    fetchAuth: fetchAuth
  };

  global.fetchAuth = fetchAuth;
})(window);

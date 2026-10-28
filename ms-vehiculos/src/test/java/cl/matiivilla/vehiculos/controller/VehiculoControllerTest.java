package cl.matiivilla.vehiculos.controller;

import cl.matiivilla.vehiculos.dto.VehiculoRequest;
import cl.matiivilla.vehiculos.dto.VehiculoResponse;
import cl.matiivilla.vehiculos.service.VehiculoService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(VehiculoController.class)
class VehiculoControllerTest {

    private static final String URL = "/api/v1/vehiculos";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private VehiculoService vehiculoService;

    private VehiculoRequest request;
    private VehiculoResponse response;

    @BeforeEach
    void setUp() {
        request = new VehiculoRequest();
        request.setPatente("ABCD12");
        request.setMarca("Toyota");
        request.setModelo("Yaris");
        request.setAnio(2020);
        request.setColor("Rojo");
        request.setTipo("Sedan");
        request.setDisponible(true);

        response = VehiculoResponse.builder()
                .id(1L)
                .patente("ABCD12")
                .marca("Toyota")
                .modelo("Yaris")
                .anio(2020)
                .color("Rojo")
                .tipo("Sedan")
                .disponible(true)
                .build();
    }

    // ---------- GET /api/v1/vehiculos ----------

    @Test
    void findAll_devuelve200ConLista() throws Exception {
        when(vehiculoService.findAll()).thenReturn(List.of(response));

        mockMvc.perform(get(URL))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].patente").value("ABCD12"));
    }

    // ---------- GET /api/v1/vehiculos/{id} ----------

    @Test
    void findById_cuandoExiste_devuelve200() throws Exception {
        when(vehiculoService.findById(1L)).thenReturn(response);

        mockMvc.perform(get(URL + "/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1))
                .andExpect(jsonPath("$.marca").value("Toyota"));
    }

    @Test
    void findById_cuandoNoExiste_devuelve404() throws Exception {
        when(vehiculoService.findById(99L))
                .thenThrow(new ResponseStatusException(HttpStatus.NOT_FOUND, "No se encontró el vehículo con id 99"));

        mockMvc.perform(get(URL + "/99"))
                .andExpect(status().isNotFound());
    }

    // ---------- POST /api/v1/vehiculos ----------

    @Test
    void create_conDatosValidos_devuelve201() throws Exception {
        when(vehiculoService.create(any(VehiculoRequest.class))).thenReturn(response);

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1))
                .andExpect(jsonPath("$.patente").value("ABCD12"));
    }

    @Test
    void create_conDatosInvalidos_devuelve400YNoLlamaAlServicio() throws Exception {
        request.setPatente("");
        request.setAnio(1900);

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest());

        verify(vehiculoService, never()).create(any());
    }

    @Test
    void create_cuandoPatenteYaExiste_devuelve409() throws Exception {
        when(vehiculoService.create(any(VehiculoRequest.class)))
                .thenThrow(new ResponseStatusException(HttpStatus.CONFLICT, "Ya existe un vehículo con la patente ABCD12"));

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isConflict());
    }

    // ---------- PUT /api/v1/vehiculos/{id} ----------

    @Test
    void update_conDatosValidos_devuelve200() throws Exception {
        response.setColor("Azul");
        when(vehiculoService.update(eq(1L), any(VehiculoRequest.class))).thenReturn(response);

        mockMvc.perform(put(URL + "/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.color").value("Azul"));
    }

    @Test
    void update_cuandoNoExiste_devuelve404() throws Exception {
        when(vehiculoService.update(eq(99L), any(VehiculoRequest.class)))
                .thenThrow(new ResponseStatusException(HttpStatus.NOT_FOUND, "No se encontró el vehículo con id 99"));

        mockMvc.perform(put(URL + "/99")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isNotFound());
    }

    // ---------- DELETE /api/v1/vehiculos/{id} ----------

    @Test
    void delete_cuandoExiste_devuelve204() throws Exception {
        mockMvc.perform(delete(URL + "/1"))
                .andExpect(status().isNoContent());

        verify(vehiculoService).delete(1L);
    }

    @Test
    void delete_cuandoNoExiste_devuelve404() throws Exception {
        doThrow(new ResponseStatusException(HttpStatus.NOT_FOUND, "No se encontró el vehículo con id 99"))
                .when(vehiculoService).delete(99L);

        mockMvc.perform(delete(URL + "/99"))
                .andExpect(status().isNotFound());
    }
}

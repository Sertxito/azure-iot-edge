# Arquitectura – IoT Edge Demo

## Flujo End‑to‑End

NodeMCU  
→ MQTT (Mosquitto)  
→ **mqtt-bridge** (IoT Edge)  
→ **edgeDecider** (IoT Edge)  
→ Cloud (opcional)

---

## Responsabilidades

### NodeMCU
- Genera telemetría
- No conoce Azure
- Formato no estable

### mqtt-bridge
- Consume MQTT
- **Normaliza payload**
- Aísla al Edge del formato del dispositivo

### edgeDecider
- Consume `input1`
- Ejecuta lógica:
  - alarmas
  - agregados
  - heartbeat
- No depende del origen del dato

---

## Regla clave

> El Edge **decide**,  
> el Cloud **observa**.

Nunca al revés.

---

## Deployment

- 1 deployment activo
- 1 route:
  mqtt-bridge → edgeDecider
- Sin rutas legacy
- Sin duplicados


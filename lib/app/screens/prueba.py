import requests
import datetime

# Configuración Supabase
SUPABASE_URL = "https://czxyfzxjwzaykwoxyjah.supabase.co/rest/v1/lecturas_rfid"
SUPABASE_API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU"
HEADERS = {
    "apikey": SUPABASE_API_KEY,
    "Authorization": f"Bearer {SUPABASE_API_KEY}",
    "Content-Type": "application/json",
    "Accept": "application/json",
}

def insertar_lectura(id_operador):
    data = {
        "id_operador": id_operador,
        "fecha_lectura": datetime.datetime.utcnow().isoformat()
    }
    response = requests.post(SUPABASE_URL, json=data, headers=HEADERS)
    if response.status_code == 201:
        print(f"Lectura RFID insertada correctamente para {id_operador}")
    else:
        print(f"Error insertando lectura RFID: {response.status_code} - {response.text}")

def leer_rfid():
    # El lector USB actúa como teclado: lee input del usuario (simula lectura)
    print("Pase tarjeta RFID:")
    codigo = input().strip()
    return codigo

def main():
    print("Iniciando lectura RFID en Raspberry Pi...")
    while True:
        id_operador = leer_rfid()
        if id_operador:
            insertar_lectura(id_operador)

if __name__ == "__main__":
    main()

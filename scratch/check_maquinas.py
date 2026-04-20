import requests
import json

URL = "https://czxyfzxjwzaykwoxyjah.supabase.co/rest/v1/maquinas?select=id_maquina,nombre"
KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}"
}

try:
    response = requests.get(URL, headers=headers)
    print(f"Status: {response.status_code}")
    print(json.dumps(response.json(), indent=2))
except Exception as e:
    print(f"Error: {e}")

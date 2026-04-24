
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://czxyfzxjwzaykwoxyjah.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN6eHlmenhqd3pheWt3b3h5amFoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MDQyODMwMCwiZXhwIjoyMDY2MDA0MzAwfQ.4An36Hs_o_aiTGfqpRC85L4jMfhfWgbAthypB0QL0yU';

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function checkOperator() {
    const { data, count, error } = await supabase
        .from('registro_tareas')
        .select('*', { count: 'exact', head: true })
        .eq('id_operador', '502');

    if (error) {
        console.error('Error:', error);
        return;
    }

    console.log(`Found ${count} records for operator 502 in registro_tareas.`);
}

checkOperator();

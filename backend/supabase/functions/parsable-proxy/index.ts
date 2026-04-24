const PARSABLE_URL = "https://api.eu-west-1.parsable.net/api/jobs";
const PARSABLE_TOKEN = Deno.env.get("PARSABLE_TOKEN") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const body = await req.text();

    const response = await fetch(PARSABLE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "accept": "application/json",
        "PARSABLE-CUSTOM-TOUCHSTONE": "heineken/heineken",
        "Authorization": PARSABLE_TOKEN,
      },
      body,
    });

    const data = await response.text();

    return new Response(data, {
      status: response.status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

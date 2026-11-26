Deno.serve(() => Response.json({
  available: false,
  code: "update_required",
  message: "Update Lulu to continue using your wallet.",
}, { status: 503, headers: { "Cache-Control": "no-store" } }));

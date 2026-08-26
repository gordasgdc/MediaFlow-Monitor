using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading.Tasks;

namespace MediaFlowMonitor.Licensing;

/// Port al RevocationCheck.swift — apelează RPC-ul `is_license_revoked`,
/// deja live în Supabase. FAIL-OPEN: fără conexiune, licența deja activată
/// local continuă să funcționeze — revocarea se aplică abia la următoarea
/// verificare online reușită.
public sealed class RevocationCheck
{
    public static readonly RevocationCheck Shared = new();

    private readonly object _lock = new();
    private readonly HashSet<string> _revokedProductIDs = new();
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(8) };

    private RevocationCheck() { }

    public bool IsRevoked(string productID)
    {
        lock (_lock) return _revokedProductIDs.Contains(productID);
    }

    private void MarkRevoked(string productID)
    {
        lock (_lock) _revokedProductIDs.Add(productID);
    }

    public async Task RefreshAsync(IEnumerable<string> productIDs)
    {
        foreach (var productID in productIDs)
        {
            var revoked = await CheckOneAsync(MachineID.Display, productID);
            if (revoked == true) MarkRevoked(productID);
        }
    }

    private static async Task<bool?> CheckOneAsync(string machineID, string productID)
    {
        if (!SupabaseConfig.ProjectURL.StartsWith("https://")) return null;
        try
        {
            var url = $"{SupabaseConfig.ProjectURL}/rest/v1/rpc/is_license_revoked";
            using var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Add("apikey", SupabaseConfig.AnonKey);
            request.Headers.Add("Authorization", $"Bearer {SupabaseConfig.AnonKey}");
            request.Content = JsonContent.Create(new { p_machine_id = machineID, p_product_id = productID });

            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode) return null; // fail-open

            var text = (await response.Content.ReadAsStringAsync()).Trim();
            // Supabase RPC pentru un `boolean` întoarce literal "true"/"false"
            // ca JSON scalar — la fel ca pe Mac (comparație directă de text).
            return text == "true";
        }
        catch
        {
            return null; // orice eroare de rețea -> fail-open, NU revocat
        }
    }
}
